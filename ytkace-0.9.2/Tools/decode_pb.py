import sys


def varint(data, offset):
    value = 0
    shift = 0
    while offset < len(data) and shift < 70:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7
    raise ValueError


def parse(data):
    fields = []
    offset = 0
    while offset < len(data):
        key, offset = varint(data, offset)
        field = key >> 3
        wire = key & 7
        if field == 0:
            raise ValueError
        if wire == 0:
            value, offset = varint(data, offset)
        elif wire == 1:
            if offset + 8 > len(data):
                raise ValueError
            value = data[offset:offset + 8]
            offset += 8
        elif wire == 2:
            length, offset = varint(data, offset)
            if offset + length > len(data):
                raise ValueError
            value = data[offset:offset + length]
            offset += length
        elif wire == 5:
            if offset + 4 > len(data):
                raise ValueError
            value = data[offset:offset + 4]
            offset += 4
        else:
            raise ValueError
        fields.append((field, wire, value))
    return fields


def text_value(data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not text or sum(ch.isprintable() for ch in text) / len(text) < 0.9:
        return None
    return text[:160]


def show(data, depth=0, limit=6):
    try:
        fields = parse(data)
    except ValueError:
        return False
    prefix = "  " * depth
    for field, wire, value in fields:
        if wire == 0:
            print(f"{prefix}{field}: varint {value}")
            continue
        if wire in (1, 5):
            print(f"{prefix}{field}: fixed {value.hex()}")
            continue
        text = text_value(value)
        print(f"{prefix}{field}: bytes {len(value)}" + (f" text={text!r}" if text else ""))
        if depth < limit and not text:
            show(value, depth + 1, limit)
    return True


with open(sys.argv[1], "rb") as source:
    show(source.read())
