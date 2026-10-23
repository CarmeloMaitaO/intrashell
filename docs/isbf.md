# IntraShell Binary Format (ISBF) especification V1.0.0

## 0. Conformance
ISBF readers and writers should accept previous versions of the specification,
but should reject future revisions of the supported versions of the
specification to prevent data corruption.

## 1. Overview
The ISBF is a binary framing format for serialization and message passing, which
means that it can be used to describe application formats, network protocols and
intra-process communication protocols (message-passing based).

It counts with the capacity to work in full and partial schemaless and schemaful
modes based on wether there are user-defined schemas and a registry within the
file/packet.

## 2. Terminology
Field, Field ID, Value, Object, Schema, Registry, Document,
Header, Data Layer, Variant Group, LAYOUT block.
  
## 3. Endianness
Little-endian, unconditionally.

## 4. Main binary structure
|    **Section**    | Header |   Data   |
| ----------------- | ------ | -------- |
| **Size in bytes** |    8   | variable |

The general structure of an ISBF file/packet is divided in:
1. Header: contains the magic bytes, plus the ISBF version and type.
3. Data: contains the actual data and, optionally, at the start, any of the
   following in their respective order:
   1. A cyclic redundancy check (CRC).
   2. A registry of the user-defined schemas.
   3. A layout of the data within the file/packet.

### Header section
|     **Field**     | Magic bytes | Version |  Flags | Type |
| ----------------- | ----------- | ------- | ------ | ---- |
| **Size in bytes** |      4      |    2    |    1   |   1  |

The header section contains the necessary information for the parser to
identify the format, the version of the specification its following and
whether it contains custom schemas or not. This information is stored in the
following fields:

1. Magic bytes: an array of 4 characters which value is
   `['I', 'S', 'B', 'F']`. It doubles as a way to check the endianness, as
   casting these bytes to an `uint32` should yield the value of
   `1178751817`.
2. Version: an array of 2 bytes with the version and revision of the
   ISBF specification that the file/packet follows. The first index is the
   version, while the second is the revision. This docunents defines the
   `[1, 0]` version of the ISBF specification.
3. Flags: a bitset of the ISBF flags that the file/packet has. The possible
   values within this specification of the ISBF are:
   1. Contains a cyclic redundacy check at the start of the data.
   2. Contains a layout section at the start of the data.
4. Type: an enumeration for the type of data contained:

   | **Number** | **Type/Contains** | Registry | User-defined schemas |
   | ---------- | ----------------- | -------- | -------------------- |
   |     0      |     Schemaless    |    No    |          No          |
   |     1      | Partial-schemaless|    Yes   |          No          |
   |     2      | Partial-schemaful |    Yes   |          Yes         |
   |     3      |      Schemaful    |    No    |          Yes         |
  
   0. Schemaless (default): no registry nor user-defined schemas. Should be used
      for simple serialization.
   1. Partial-schemaless: have a registry but no user-defined schemas; this is to
      simply declare ordering, length and constraints of the transmitted data.
      It accepts schemaless inputs for parsing, as in this scenario, the
      registry acts as a self-contained way of performing input-sanitization.
   1. Partial-schemaful: contains a registry and user-defined schemas; This
      should always be used for file/application formats, as it facilitates the
      inspection of the data without a dedicated parser.
   2. Schemaful: contains user-defined schemas, but no registry. This should
      always be used for network protocols and intra-process communication, as
      it significantly reduces the amount of bytes wasted for every sent
      package. To parse the data, the registry should be pre-shared. This type
      is enforced for Intrashell modules.

### Data section
    |     **Field**     | CRC | Registry |  Layout  |   Data   |
    | ----------------- | --- | -------- | -------- | -------- |
    | **Size in bytes** |  4  | variable | variable | variable |

    The data section contains the information being transmitted, and, depending
    on the flags declared in the header, metadata of said information. That
    said, the data and the metadata always follows the ordering shown in the
    table, even when some or all metadata sections are missing, in which case
    the aforementioned section will be interpreted to have a size of `0` bytes,
    and be skipped while parsing.

    Regarding the contents of the data and its metadata, and how shall they be
    parsed; it is intended for every single section and its fields to be
    interpreted the exact same way as the contents of the data would: a `uint16`
    ID is read, and its following fields are known based on it, to then continue
    to read the next ID; the only exception to this rule is the CRC section,
    for it always is an `uint32` field.

    Also, every single field should be composed of an array of `uint16` values,
    or padded in a way that wouldn't cause a misalignment in the file/packet
    structure, as every ID and its following fields should be in a position that
    is a multiple of `2` bytes or `16` bits.

## 5. Base types/IDs
    The first `255` ID values are reserved for the base types/IDs of this
    specification and future ones, with the ones being defined in this
    document being:

    0. Registry
    1. Schema definition
    2. Variant group definition
    3. Layout
    4. BLOB
    5. String
    6. Array
    7. Bool
    8. Int8
    9. Uint8
    10. Int16
    11. Uint16
    12. Int32
    13. Uint32
    14. Float32
    15. Int64
    16. Uint64
    17. Float64

### Registry type (ID: 0)
    |     **Field**     | ID  |   Name   | Version | Elements |
    | ----------------- | --- | -------- | ------- | -------- |
    | **Size in bytes** |  2  |    40    |    2    |     2    |

    Indicates the presence and start of a registry section within the data. Its
    fields are:

    1. Name: the name of the registry. This field is used to
       identificate the user's application format/protocol/buffer
    2. Version: the version of the user's application format/protocol/buffer.
       It is an array of 2 bytes with the version and revision of the format.
    3. Elements: the number of elements contained within the registry. After
       processing all of them, the registry should be cinsidered finished, and
       any new definitions should make the parser exit and notify that the file
       is corrupted.

### Schema definition type (ID: 1)
    |     **Field**     | ID  |   Name   | Schema ID | Elements |
    | ----------------- | --- | -------- | --------- | -------- |
    | **Size in bytes** |  2  |    40    |     2     |     2    |

