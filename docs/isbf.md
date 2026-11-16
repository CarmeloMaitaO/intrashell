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
- Data: the second section of an ISBF message, that contains combinations of
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

## 4. Main binary structure

|    **Section**    | Header |   Data   |
| ----------------- | ------ | -------- |
| **Size in bytes** |   16   | variable |

The general structure of an ISBF message is divided in:
1. Header: contains the magic bytes and version for both the ISBF and the
description.
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

## 5. Basic wrapper container

Every single field is contained within wrapper container composed of an array
of 16 bits (or 2 bytes) limbs, as to keep the structure aligned and the padding
implicit. To wrap them, the following formula is used: `limbs = (fieldSize
div 2) + (fieldSize mod 2)`, which can be read as the integer coefficient of
half field size, plus its remainder. This container also happens to be preceded
by a limb which contains the ID of the field, with the basic form of every field
being:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  | variable |

Furthermore, this containers structure can vary depending on the classification
of the field it's wrapping, and whether a fixed size has been set for it or not,
with the existing classifications being:

- Atomic fields
- Container fields
- Objects
- Object Variants

### Atomic fields

Atomic fields remain almost identical to the basic form, with the sole
distinction over their structure being whether they are fixed or flexible sized:

- **Fixed sized structure**:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |  Fixed   |

In this scenario, the size in limbs of the value has already been set, and
there's no need to add further information to help with it's parsing.

- **Flexible sized structure**:

| **Semantic value** | ID | Size |  Value   |
| ------------------ | -- | ---- | -------- |
| **Size in limbs**  | 1  |   1  | variable |

In this case, an additional `Size` section is added to indicate how many limbs
compose the following value, and is treated as a single 16 bits unsigned
integer.

> Atomic fields are the only ones that don't need to declare if the last limb
is completely used or not.

### Container fields

Container fields stand a single level above atomic fields, as they remain
largely similar, but forces the use of the `Size` section regardless of whether
the field is fixed or flexible sized, and treats this section as an arbitrary
length signed integer, which indicates with it's sign whether the last limb of
the value is fully used or not; negative if only the first byte is used,
positive if both bytes are used.

- **Fixed size structure**:

| **Semantic value** | ID |  Size |  Value   |
| ------------------ | -- | ----- | -------- |
| **Size in limbs**  | 1  | Fixed |   Fixed  |

In the case of a fixed size container, both the `Size` and the `Value` sections
are fixed size, but that doesn't mean that the last section is going to be fully
used, as the container is the one with the fixed size, not the data it contains,
hence the need for the `Size` section.

- **Flexible size structure**:

| **Semantic value** | ID |    Size   |  Value   |
| ------------------ | -- | --------- | -------- |
| **Size in limbs**  | 1  | Arbitrary | variable |

For flexible size containers, the length of the `Size` section is direcly
derived from the actual length of the `Value` based on the necessary amount
of limbs to represent the number of bytes contained, and from said number, the
number of limbs that contains the value is derived.

### Array fields

Array fields stand one level above container fields, and are the firsts of the
abstract fields, as they are meant to hold a list of elements of another type,
so it's impossible to make assumptions over it's structure and data without
knowing the type the store first.

In this sense, the `Size` section of an array can only represent the number of
elements stored within the structure from the start, giving no information
regarding the actual amount of limbs that hold the data without knowing the
stored type first. Also, this section is interpreted as an arbitrary length
unsigned integer.

It is worth noting that the elements inside an array omit their ID limb, as it
is known beforehand. This serves as a way to optimize storage/memory space, as
less limbs are required for identification.


- **Fixed size structure**:

| **Semantic value** | ID |  Size |  Elements   |
| ------------------ | -- | ----- | ----------- |
| **Size in limbs**  | 1  | Fixed |    Fixed    |

> In this scenario it is only possible to store fixed size types.

A fixed size array has a set amount of limbs and slots to store its elements,
with its `Size` section representing the amount of used slots from the start of
the container.

- **Flexible size structure**:

| **Semantic value** | ID |    Size   | Elements |
| ------------------ | -- | --------- | -------- |
| **Size in limbs**  | 1  | Arbitrary | variable |

> In this scenario it is possible to store both fixed and flexible size types.

Flexible size arrays have a variable amount of elements, and as many slots as
elements are currently present within it.

### Bitfields

Bitfields are the second of the abstract types, and stand one level above arrays
in terms of abstraction. They are meant to be used to split one or multiple
limbs into heterogeneous sequences of bits, which will become subfields for it,
replicating the behaviour of an object/tuple at a smaller scale, but with the
constraint of interpreting every subfield as an unsigned integer, and each of
them not being bigger than 15 bits.

> Bitfields are always fixed size, as they have a well defined structure, by
which they are also treated as fixed size atomic types.

- **Fixed size structure**:

| **Semantic value** | ID |   Limbs  |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |   Fixed  |

While the core value is fixed size, its bits will be splitted to get the
contained subfields within it. These subfields shall be defined inside the
interface description file of the respective ISBF dialect.

> Subfields carry no ID, only their value.

### Objects

Objects are essentially the same as bitfields; the only difference is that the
fields can be of any type (including other objects) and they use full limbs
instead subsets of their bits.

It is worth noting that the fields inside an object omit their ID limb, as it
can be inferred from the order within the object. This serves as a way to
optimize storage/memory space, as less limbs are required for identification.

> Objects are fixed or flexible size depending on whether all their fields are
fixed size or not.

- **Fixed/Flexible size structure**:

| **Semantic value** | ID |       Fields      |
| ------------------ | -- | ----------------- |
| **Size in limbs**  | 1  |   Fixed/Flexible  |

In a fixed size object, fields can be accessed based on their position, whereas
in a flexible size one, they must be sequentially read until the desired one is
found.

### Variants

Variants stand at the top of the abstraction levels, and they enable the use of
different types inside the same field, constrained by a list of allowed types,
and the use of its ID. In this sense, they are the ISBF equivalent to Nim's
object variants.

> Variants are fixed or flexible sized depending on whether all their allowed
types are fixed size or not. In the case of being fixed size, the common size
will be of the biggest allowed type.

- **Fixed/Flexible size structure**:

| **Semantic value** | ID of the field type |       Field       |
| ------------------ | -------------------- | ----------------- |
| **Size in limbs**  |           1          |   Fixed/Flexible  |

Variants and their allowed types are to be defined inside the interface
description file of the ISBF dialect, and to be used within the definitions of
other types to avoid having to declare each allowed combination of fields as
multiple, different types.

### Padding/skip

For every empty slot or field in any of the previous type, a padding/skip limb
is added, as to allow the parser to continue reading the next limb until the
next field is found. This limb is fully zeroed to make identifying it easier.

In the case the Padding/skip limb is in the position of what would be an ID in
a fixed size type, then the parser can skip to the next field without reading
the limbs within the current type, as it is considered now empty.

## 6. Built-in ISBF dialect for dialect definition

To create and share new ISBF dialects it is necessary to first create an
interface definition file, which comes in the form of another ISBF file with
a predefined dialect, which has as the dialect's magic bytes
`[0, 0, 0, 0, 0, 0, 0, 0]`.

### Base types/IDs

The first `0xFF` ID values from `0x0` are reserved for the base
types/sections/IDs of this specification and future ones, with the ones being
defined in this document being:

3.  (0x3) BLOB
4.  (0x4) String
5.  (0x5) Natural
6.  (0x6) Integer
7.  (0x7) Rational
8.  (0x8) Boolean

## 8. File termination

## 9. Versioning

## 10. Error handling

## 11. Security

## 12. Providing ACID

### Atomicity

### Consistency

### Isolation

### Durability
