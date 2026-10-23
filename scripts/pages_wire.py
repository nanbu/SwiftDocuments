"""Small independent IWA wire utility for fixture sanitation and public-content auditing.

This is tooling, not the Swift codec. Supports bounded iWork Snappy chunks and
wire fields 0/1/2/5; never executes source document data.
"""
import struct

MAX_BYTES = 128 * 1024 * 1024


def varint(data, position=0):
    result = 0
    for shift in range(0, 70, 7):
        if position >= len(data): raise ValueError('truncated varint')
        byte = data[position]; position += 1
        if shift == 63 and byte > 1: raise ValueError('overflowing varint')
        result |= (byte & 127) << shift
        if byte < 128: return result, position
    raise ValueError('overflowing varint')


def encode_varint(value):
    result = bytearray()
    while value >= 128:
        result.append(value & 127 | 128); value >>= 7
    result.append(value)
    return bytes(result)


def fields(data):
    result = []; position = 0
    while position < len(data):
        start = position; tag, position = varint(data, position)
        key, wire = tag >> 3, tag & 7
        if not 0 < key <= 536870911: raise ValueError('invalid field')
        if wire == 0: value, position = varint(data, position)
        else:
            if wire == 2: count, position = varint(data, position)
            elif wire in (1, 5): count = 8 if wire == 1 else 4
            else: raise ValueError('unsupported wire type')
            if count > len(data) - position: raise ValueError('truncated field')
            value = bytes(data[position:position + count]); position += count
        result.append((key, wire, value, bytes(data[start:position])))
    return result


def scalar(data, key):
    values = [value for k, w, value, raw in fields(data) if k == key and w == 0]
    if len(values) != 1: raise ValueError('missing / duplicate scalar')
    return values[0]


def field(key, value, wire=2):
    return encode_varint(key << 3 | wire) + (encode_varint(value) if wire == 0 else encode_varint(len(value)) + value)


def decode_iwa(data):
    output = bytearray(); cursor = 0
    while cursor < len(data):
        if len(data) - cursor < 4 or data[cursor] != 0: raise ValueError('invalid IWA frame')
        count = int.from_bytes(data[cursor + 1:cursor + 4], 'little'); cursor += 4
        if count > len(data) - cursor: raise ValueError('truncated IWA frame')
        chunk = data[cursor:cursor + count]; cursor += count
        size, position = varint(chunk)
        if size > MAX_BYTES - len(output): raise ValueError('expanded IWA limit')
        decoded = bytearray()
        while position < len(chunk):
            tag = chunk[position]; position += 1; kind = tag & 3
            if kind == 0:
                length = (tag >> 2) + 1
                if length > 60:
                    width = length - 60
                    if width > len(chunk) - position: raise ValueError('truncated literal length')
                    length = int.from_bytes(chunk[position:position + width], 'little') + 1; position += width
                if length > len(chunk) - position or length > size - len(decoded): raise ValueError('invalid literal')
                decoded += chunk[position:position + length]; position += length
            else:
                width = 1 if kind == 1 else 2 if kind == 2 else 4
                if width > len(chunk) - position: raise ValueError('truncated copy')
                offset = int.from_bytes(chunk[position:position + width], 'little'); position += width
                length = ((tag >> 2) & 7) + 4 if kind == 1 else (tag >> 2) + 1
                if kind == 1: offset |= (tag & 224) << 3
                if not 0 < offset <= len(decoded) or length > size - len(decoded): raise ValueError('invalid copy')
                for _ in range(length): decoded.append(decoded[-offset])
        if len(decoded) != size: raise ValueError('Snappy length mismatch')
        output += decoded
    return bytes(output)


def encode_iwa(data):
    output = bytearray()
    for start in range(0, len(data), 65536):
        chunk = data[start:start + 65536]; size = len(chunk)
        literal = bytes(((size - 1) << 2,)) if size <= 60 else bytes((244,)) + struct.pack('<H', size - 1)
        compressed = encode_varint(size) + literal + chunk
        output += b'\0' + len(compressed).to_bytes(3, 'little') + compressed
    return bytes(output)


def remove_printer(data):
    """Remove TP.DocumentArchive field 43; preserve every other message byte."""
    output = bytearray(); position = 0
    while position < len(data):
        size, position = varint(data, position)
        if size > len(data) - position: raise ValueError('truncated archive header')
        header = data[position:position + size]; position += size
        rebuilt = bytearray(); payloads = bytearray()
        for key, wire, value, raw in fields(header):
            if key != 2:
                rebuilt += raw; continue
            length = scalar(value, 3)
            if length > len(data) - position: raise ValueError('truncated archive payload')
            payload = data[position:position + length]; position += length
            if scalar(header, 1) == 1 and scalar(value, 1) == 10000:
                payload = b''.join(raw for k, w, v, raw in fields(payload) if k != 43)
                value = b''.join(field(3, len(payload), 0) if k == 3 else raw for k, w, v, raw in fields(value))
            rebuilt += field(2, value); payloads += payload
        output += encode_varint(len(rebuilt)) + rebuilt + payloads
    return bytes(output)
