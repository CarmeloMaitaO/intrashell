# IntraShell Binary Format (ISBF) especification V1.0

## 0. Conformance

ISBF readers and writers should accept previous versions of the specification,
but should reject future revisions of the supported versions of the
specification to prevent data corruption.

## 1. Overview

ISBF is a schemaful binary framing format, designed to define new binary
formats and the contracts they are constrained to, in an interface description
file that is consumed by the main ISBF parser.

This interface description file is written in a predefined ISBF dialect that
allows to define new objects, their fields, and their constraints, with every
field being derived from one of the ISBF built-in types, which all are
aligned to 16 bits and have flexible sizes, as they all behave like containers,
with the sole exception being numbers (natural, integer, rational), as they
are arbitrary-length, with their limbs being composed of 16 bits.

In this way, ISBF serves not only as a data serialization format, but also
as a foundation for building application file formats, network protocols, and
inter-/intra-process communication protocols based on zero-copy message-passing,
while remaining future proof thanks to their abstract, variable-length types.

## 2. Terminology

- ISBF dialect: a binary format made with an ISBF interface description file.
- Section: a group of bytes within a given memory space.
- Message: a single ISBF packet/file and root container for the header and data
sections.
- Schema: the shape and constraints of a message, section or object.
- Header: the first section of an ISBF messsage. It contains the information for
the parser to know that is an ISBF and how it should interpret the rest of the
data and its layout.
- Metadata: the second section of an ISBF message. Provides additional
information related to the integrity, layout, encription and compression of the
ISBF message.
- Data: the third section of an ISBF message, that contains combinations of
objects, constrained by the definitions of the ISBF dialect.
- Object: an heterogeneous, ordered container of different fields.
- Field: a single data element of a determinate type.
- Magic bytes: a set of either four or eight bytes that identify the
message's format.
- ID: a 16-bit number that identifies a section, object or field.
  
## 3. Endianness

Little-endian, unconditionally. This applies to:

- Magic bytes
- IDs
- Numbers
- Bitfields
- Booleans

## 4. Basic data structure

Every single field is contained within a 16bits wrapper, as to keep the
structure aligned and the padding implicit. To wrap them, the following formula
is used: `u16Pairs = (fieldSize div 2) + (fieldSize mod 2)`, which can be read
as the integer coefficient of half field size, plus its remainder.

## 5. Main binary structure

|    **Section**    | Header | Metadata |   Data   |
| ----------------- | ------ | -------- | -------- |
| **Size in bytes** |   16   | variable | variable |

The general structure of an ISBF message is divided in:
1. Header: contains the magic bytes and version for both the ISBF and the
description.
2. Metadata: optional, and may contain the layout and an integrity check for
the data, along with any information about the encryption and compression of
said data.
3. Data: contains the actual data.

### Header section

|     **Field**     | Magic bytes | Version |  Dialect's MB | Dialect's version |
| ----------------- | ----------- | ------- | ------------ | ---------------- |
| **Size in bytes** |      4      |    2    |        8     |         2        |

The header section contains the necessary information for the parser to identify
the format and the version of the specification its following. This information
is stored in the following fields:

1. Magic bytes: an array of 4 characters which value is
   `['I', 'S', 'B', 'F']`.
2. Version: an `uint16` with the major version of the ISBF specification that
   the file/packet follows. This docunents defines the `1` version of the ISBF
   specification.
3. dialect's magic bytes: The magic bytes of the ISBF dialect.
   These are auto-generated from the dialect's name set in the interface
   description file, by hashing it with SHA-256 and taking the first 8 bytes.
4. dialect's version: an `uint16` that defines the major version of the dialect
   defined by the interface description file.

### Data section

|     **Field**     |   Data   |
| ----------------- | -------- |
| **Size in bytes** | variable |

The data section contains the information being transmitted.

Regarding the contents of the data, and how shall it be
parsed; it is intended for every single section and its fields to be
interpreted the exact same way as the contents of the data would: a `uint16`
ID is read, and its following fields are known based on it, to then continue
to read the next ID.

## 6. Base types/IDs

The first `0xFF` ID values from `0x0` are reserved for the base
types/sections/IDs of this specification and future ones, with the ones being
defined in this document being:

0.  (0x0) Padding/Skip
1.  (0x1) Metadata
2.  (0x2) Array
3.  (0x3) BLOB
4.  (0x4) String
5.  (0x5) Natural
6.  (0x6) Integer
7.  (0x7) Rational
8.  (0x8) BitField
9.  (0x9) Object
10. (0xA) Object variant

### Padding/Skip

The padding/skip type is meant to be safeguard against empty sections, so the
parser can skip reading it and move onto the next value expecting an ID.

### Metadata

Given that the parser should expect the data section just after the header, the
metadata section is given an ID so it can be detected. It should be the first ID
to be detected when parsing an ISBF message, otherwise the parser should error
out.

Also, the metadata is to be redefined at the ISBF dialect's interface
description file, otherwise it should not be present within any message at all.

### Array

An array wraps a finite list of another type/object instances. It does so by
first declaring the type/object being wrapped and then the number of elements
inside a `natural`. It is possible to declare a defined size for the array
inside the ISBF dialect's interface description file, with the empty slots being
filled with `padding/skip` values and the length of the array being the actual
amount of elements within it from the first index.

### Binary Large Object (BLOB)

A BLOB is an universal container for binary data that doesn't fall inside any of
the provided types, and is supposed to be interpreted by an 

### String

### Natural

### Integer

### Rational

### BitField

### Object

### Object Variant

## 7. Built-in ISBF dialect for dialect definition

To share the description of an schema before sharing data, one uses and
additional message with the schema ID `0`, followed by the description inside
the data section. This is 

## 8. Section termination

## 9. Versioning

## 10. Error handling

## 11. Security
