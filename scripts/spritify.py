#
# Generate Sprite graphics for the VCS
# can generate 8 bit, 24, or 48 bit sprites
# 8 bit supports converting higher res images
# by also manipulating control and hmov registers
#

import sys
import subprocess
import os
from os import path
import glob
from PIL import Image
import itertools
from collections import namedtuple
import queue
from dataclasses import dataclass, field
import argparse

explicit_zero = False

def pairwise(iterable):
    a, b = itertools.tee(iterable)
    next(b, None)
    return zip(a, b)

def chunker(iterable, n):
    args = [iter(iterable)] * n
    return itertools.zip_longest(*args)

def aseprite_save_as(input, output):
    print(f'converting: {input} -> {output}')
    out = subprocess.run([f'aseprite', '-b', input, '--save-as', output])
    out.check_returncode()


def is_black(pixel):
    return (sum(pixel[0:2]) / 3.0) < 128 and (len(pixel) < 4 or pixel[3] < 10)

def bit(pixel):
    return 0 if is_black(pixel) else 1

def bits2int(bits):
    return int(''.join([str(bit) for bit in bits]), 2)

def int2asm(i):
    return '$' + hex(i)[2:]

def anybits(bits):
    return 1 if sum(bits) > 0 else 0

def reduce_bits(bits, n):
    return [anybits(chunk) for chunk in chunker(bits, n)]

def complement(n, b):
    if n >= 0:
        return n
    return b + n

def hmove(n):
    return complement(-n, b=16) * 16

CompressedBits = namedtuple('CompressedBits', ['scale', 'start_index', 'end_index', 'bits'])

# compress an array of bits to a single byte at single, double or quad resolution
# return tuple of 
def compress8(bits):
    start_index = len(bits)
    end_index = -1
    for i, b in enumerate(bits):
        if 0 == b:
            continue
        if i < start_index:
            start_index = i
        if i > end_index:
            end_index = i
    bits = bits[start_index:end_index + 1]
    bit_length = len(bits)
    if (bit_length <= 8):
        return CompressedBits(1, start_index, end_index, bits)
    if (bit_length <= 16):
        pad = bit_length % 2
        bits = bits + ([0] * pad)
        end_index += pad
        return CompressedBits(2, start_index, end_index, reduce_bits(bits, 2))
    pad = 4 - bit_length % 4
    bits = bits + ([0] * pad)
    end_index += pad
    return CompressedBits(4, start_index, end_index, reduce_bits(bits, 4))

def nusize(i):
    if i == 1:
        return 0
    return i + 3

def paddings(a):
    nbits = len(a.bits)
    pad = 8 - nbits
    for lpad in range(0, pad + 1):
        rpad = pad - lpad
        bits = [0] * lpad + a.bits + [0] * rpad
        start_index = a.start_index - lpad * a.scale
        end_index = a.start_index + 8 * a.scale
        yield start_index, end_index, bits

def is_legal_hmove(i):
    return i < 8 and i > -9

@dataclass(order=True)
class SolutionItem:
    priority: int
    steps: object = field(compare=False)
    frontier: object = field(compare=False)

def find_offset_solution(compressedbits, solve_left=True, solve_right=False):
    solutions = queue.PriorityQueue()
    base_priority = 10 * (len(compressedbits) - 1)
    max_depth = len(compressedbits)

    leading_steps = []
    while len(compressedbits) > 0:
        first_nonzero_row = compressedbits[0]
        compressedbits = compressedbits[1:]
        if len(first_nonzero_row.bits) > 0:
            break
        leading_steps.append((0, 0, (0, 0, [0] * 8)))

    for a in paddings(first_nonzero_row):
        solutions.put(SolutionItem(base_priority, leading_steps + [(0, 0, a)], compressedbits))

    while not solutions.empty():
        item = solutions.get()
        _, _, a = item.steps[-1]
        b = item.frontier[0]
        max_depth = min(max_depth, len(item.frontier))
        if len(b.bits) == 0:
            candidates = [(a[0], a[1], [0] * 8)]
        else:
            candidates = paddings(b)
        for candidate in candidates:
            lmove = candidate[0] - a[0]
            rmove = candidate[1] - a[1]
            if solve_left and not is_legal_hmove(lmove):
                continue
            if solve_right and not is_legal_hmove(rmove):
                continue
            next_step = (lmove, rmove, candidate)
            next_solution = item.steps + [next_step]
            if len(item.frontier) == 1:
                return next_solution
            else:
                cost = item.priority + abs(lmove) + abs(rmove) - 10
                solutions.put(SolutionItem(cost, next_solution, item.frontier[1:]))
    raise Exception(f'cannot find solution at depth {max_depth}')
            
# variable resolution sprite
def emit_varsprite8(varname, image, fp, reverse=False):
    width, _ = image.size
    if not image.mode == 'RGBA':
        image = image.convert(mode='RGBA')
    data = image.getdata()
    rows = chunker(map(bit, data), width)
    if reverse:
        rows = [tuple(reversed(row)) for row in rows]

    compressedbits = list([compress8(list(row)) for row in rows])
    solution = find_offset_solution(compressedbits, solve_left=True)

    left_delta = list([step[0] for step in solution[1:]] + [0])
    padded_bits = list([step[2][2] for step in solution])

    nusizes = list([ nusize(cb.scale) for cb in compressedbits])
    ctrl = list([hmove(offset) + size for offset, size in zip(left_delta, nusizes)])
    graphics = list([bits2int(bits) for bits in padded_bits])

    # write output
    for name, col in [('ctrl', ctrl), ('graphics', graphics)]:
        value = ','.join([int2asm(word) for word in reversed(col)])
        fp.write(f'{varname}_{name}\n'.upper())
        fp.write(f'    byte {value}; {len(col)}\n')

# multi-player sprite
def emit_spriteMulti(varname, image, fp, bits=24):
    width, height = image.size
    if not image.mode == 'RGBA':
        image = image.convert(mode='RGBA')
    data = image.getdata()
    cols = int(bits / 8)
    vars = [[]] * cols
    for i, word in enumerate([bits2int(chunk) for chunk in chunker(map(bit, data), 8)]):
        vars[i % cols].append(word)
    fp.write(f'{varname}\n'.upper())
    for col in vars:
        value = ','.join([int2asm(word) for word in reversed(col)])
        fp.write(f'\t\t\t\tbyte\t{value}; {len(col)}\n')

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Generate 6502 assembly for sprite graphics')
    parser.add_argument('--reverse', type=bool, default=False)
    parser.add_argument('--bits', type=int, choices=[8, 24, 48], default=8)
    parser.add_argument('filenames', nargs='*')

    args = parser.parse_args()

    sprites = {}
    
    for filename in args.filenames:
        spritename, ext = os.path.splitext(path.basename(filename))
        aseprite_save_as(filename, f'data/{spritename}_001.png')
        sprites[spritename] = sorted(list(glob.glob(f'data/{spritename}_*.png')))

    out = sys.stdout
    for spritename, files in sprites.items():
        for i, filename in enumerate(files):
            varname = f'{spritename}_{i}'
            with Image.open(filename, 'r') as image:
                width, _ = image.size
                if args.bits > 8:
                    emit_spriteMulti(varname, image, out, bits=args.bits)
                elif width == 8:
                    emit_spriteMulti(varname, image, out, bits=8)
                else:
                    emit_varsprite8(varname, image, out, reverse=args.reverse)

        
