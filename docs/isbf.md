# IntraShell Binary Format (ISBF) especification V1.0

## 0. Conformance

ISBF readers and writers should accept previous versions of the specification,
but should reject future revisions of the supported versions of the
specification to prevent data corruption.

## 1. Overview

ISBF is a pseudo-schemaful binary framing format capable of operating in both
schemaless and schemaful modes, depending on when the schema description is
shared: before or alongside the message payload itself.

In this way, ISBF serves not only as a data serialization format, but also
as a foundation for building application file formats, network protocols, and
inter-/intra-process communication protocols based on message-passing.

## 2. Terminology

- Section: a group of bytes within a given memory space.
- Message: a single ISBF packet/file and root container for the header, data,
and optionally, description sections.
- Schema: the shape and constraints of a message, section or object.
- Header: the first section of an ISBF messsage. It contains the information for
the parser to know that is an ISBF and how it should interpret the rest of the
data and its layout.
- Description: the second section of an ISBF message, that may be included
in the message in schemaless mode, while left out in schemaful mode, that
encapsulates the different shapes of the messages, the objects they may contain,
and the schema that, together, they form. It can also put constraints on the
metadata section.
- Metadata: the third section of an ISBF message. Provides additional
information related to the integrity, layout, encription and compression of the
ISBF message.
- Data: the fourth section of an ISBF message, that contains combinations of
objects, constrained by the definitions of the description.
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

## 4. Basic data structure

Every single field is contained within a 16bits wrapper, as to keep the
structure aligned and the padding implicit. To wrap them, the following formula
is used: `u16Pairs = (fieldSize div 2) + (fieldSize mod 2)`.

## 5. Main binary structure

|    **Section**    | Header | Description | Metadata |   Data   |
| ----------------- | ------ | ----------- | -------- | -------- |
| **Size in bytes** |   16   |   variable  | variable | variable |

The general structure of an ISBF message is divided in:
1. Header: contains the magic bytes and version for both the ISBF and the
description.
2. Description: contains the definitions for objects, their ordering within a
message and the constraints that their fields are subjected to. It also provides
constraints for the metadata section of the ISBF message.
3. Metadata: optional, and may contain the layout and CRC check for the data,
along with any information about the encryption and compression of said data.
4. Data: contains the actual data.

### Header section

|     **Field**     | Magic bytes | Version |  Schema's MB | Schema's version |
| ----------------- | ----------- | ------- | ------------ | ---------------- |
| **Size in bytes** |      4      |    2    |        8     |         2        |

The header section contains the necessary information for the parser to identify
the format and the version of the specification its following. This information
is stored in the following fields:

1. Magic bytes: an array of 4 characters which value is
   `['I', 'S', 'B', 'F']`. It doubles as a way to check the endianness, as
   casting these bytes to an `uint32` should yield the value of
   `1178751817` on a little endian architecture, and `1230193222` on a big
   endian one. The little endian one is the enforced.
2. Version: an `uint16` with the major version of the ISBF specification that
   the file/packet follows. This docunents defines the `1` version of the ISBF
   specification.
3. Schema's magic bytes: The magic bytes of the schema defined in the
   description section. These are auto-generated from the schema name set in the
   description, by hashing it with SHA-256 and taking the first 8 bytes.
4. Schema's version: an `uint16` that defines the major version of the schema
   defined by the description section.

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

## 6. Reserved schema for description/schema sharing

To share the description of an schema before sharing data, one uses `0` as the
magic bytes of the schema inside the header, followed by the description. This
way, it is know that the ISBF message is just the description of another schema,
and that there is no data to read.

## 7. Base types/IDs

The first `255` ID values are reserved for the base types/sections/IDs of this
specification and future ones, with the ones being defined in this
document being:

0. Padding/Skip
1. Description
2. BitField definition
3. Object definition
4. Object variant definition
5. Message definition
6. Metadata
7. Layout
8. Array
9. BLOB
10. String
11. Natural
12. Integer
13. Rational
