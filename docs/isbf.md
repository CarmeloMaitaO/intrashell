# IntraShell Binary Format (ISBF) specification V1.0

## 0. Conformance

ISBF readers and writers should accept previous versions of the specification,
but should reject future revisions of the supported versions of the
specification to prevent data corruption.

## 1. Overview

The IntraShell Binary Format (ISBF) is a self-describing, schema-driven,
block-level metaformat abstraction optimized for block allocation and
concurrent I/O. It is intended as the paging and framing layer on which
developers can build their own file formats, data stores, filesystems, and
communication protocols from first principles — without reinventing block
framing, page recovery, or endianness handling.

ISBF sits below database engines such as SQLite (which provide paging, B-Trees,
transactions, and query layers on top of a block layer) and above encoding
rules such as ASN.1 (which describe only field encoding, not block layout or
recovery). In this sense, ISBF is a *metaformat*: it is used to define
dialects, and those dialects are themselves ISBF documents.

## 2. Terminology

- **ISBF dialect**: a binary format defined using an ISBF interface
  description file. A dialect specifies the shape and constraints of
  messages, sections, objects, and fields that conform to it.
- **Interface description file**: an ISBF message whose dialect magic bytes
  are all-zeros (`[0,0,0,0,0,0,0,0]`). It contains the declaration of a
  dialect and is itself a valid ISBF message.
- **Message**: a single ISBF packet or file. It is the root container for the
  header and data sections.
- **Header**: the first section of an ISBF message. It contains the ISBF
  magic bytes, the ISBF version, the dialect's magic bytes, and the dialect's
  version.
- **Data**: the second section of an ISBF message. It contains a single
  field/object from the dialect, optionally preceded by an embedded interface
  definition.
- **Section**: a group of bytes within a message.
- **Schema**: the shape and constraints of a message, section, or object.
- **Object**: a heterogeneous, ordered container of fields.
- **Field**: a single data element of a determined type.
- **Limb**: a 16-bit (2-byte) unit. Every field is composed of one or more
  limbs. Limbs are the minimum addressable unit of an ISBF message.
- **Slot**: the fixed-size allocation for a field, declared in the dialect. A
  field occupies its full slot regardless of the amount of data it actually
  uses. Padding within a slot is implicit.
- **Magic bytes**: 4 bytes identifying the ISBF format (`['I','S','B','F']`),
  or 8 bytes identifying a dialect (derived from the dialect's name via
  truncated SHA-256).
- **ID**: a 16-bit number that identifies a section, object, or field.
- **Metaformat**: a format for defining other formats. ISBF is a metaformat
  because dialects are themselves ISBF documents.
- **Trace event**: an informational parse event describing what the parser is
  doing. Trace events are not errors; they are emitted only when tracing is
  enabled.
- **Error (hard)**: a parse failure that prevents further parsing. The parser
  must stop immediately.
- **Error (parseable)**: a parse failure that permits continued parsing. The
  application may inspect the partially-parsed result, or may choose to abort.

## 3. Endianness

ISBF uses little-endian byte order unconditionally. This applies to:

- Magic bytes (interpreted as a `uint32`)
- IDs (`uint16`)
- Numeric fields of all widths
- Floating-point fields (IEEE 754)
- Bitfield container limbs (but subfields within a limb are packed LSB-first,
  per Section 5)
- Boolean values

### Bit-level ordering for bitfields

Subfields within a bitfield are packed starting from the least-significant bit
of the first limb: the first declared subfield occupies bits `[0..N-1]` of
limb 1, the next occupies bits `[N..M-1]`, and so on. A subfield that does not
fit in the remaining bits of a limb continues at bit 0 of the next limb. The
total declared width of all subfields must equal the declared limb count of the
bitfield times 16.

### Interpreting the magic bytes

The 4-byte magic byte sequence `['I','S','B','F']`, interpreted as a
little-endian `uint32`, has the value `0x46425349`. This value doubles as a
sanity check: a big-endian reader interpreting the same bytes as a `uint32`
would obtain `0x49534246`, which does not match `0x46425349`. ISBF mandates
that readers detect this mismatch and reject the message as an endianness
violation.

## 4. Main binary structure

|    **Section**    | Header |   Data   |
| ----------------- | ------ | -------- |
| **Size in bytes** |   16   | variable |

The general structure of an ISBF message is divided into:

1. **Header**: contains the magic bytes and version for both the ISBF format
   and the dialect.
2. **Data**: contains the actual data.

### Header section

|     **Field**     | Magic bytes | Version | Dialect's MB | Dialect's version |
| ----------------- | ----------- | ------- | ------------ | ----------------- |
| **Size in bytes** |      4      |    2    |       8      |         2         |

The header section contains the necessary information for the parser to
identify the format and the version of the specification it follows. This
information is stored in the following fields:

1. **Magic bytes**: an array of 4 characters whose value is
   `['I','S','B','F']`.
2. **Version**: a `uint16` with the major version of the ISBF specification
   that the file/packet follows. This document defines version `1` of the
   ISBF specification.
3. **Dialect's magic bytes**: the magic bytes of the ISBF dialect. These are
   auto-generated from the dialect's name as set in the interface description
   file, by hashing the name (as UTF-8 bytes) with SHA-256 and taking the
   first 8 bytes of the digest.
4. **Dialect's version**: a `uint16` that defines the major version of the
   dialect defined by the interface description file.

### Data section

|     **Field**     |   Data   |
| ----------------- | -------- |
| **Size in bytes** | variable |

The data section contains the information being transmitted.

Regarding the contents of the data and how it shall be parsed: a single
field/object from the ISBF dialect is expected, with an optional, embedded
interface definition of said dialect as its first field, so the schema can be
recovered from the file itself. This provides a way to preserve the
readability of files across time, even if the original interface description
is lost in the future.

## 5. Basic wrapper container and data fields/objects

Every single field is contained within a wrapper container composed of an
array of 16-bit (or 2-byte) limbs, so as to keep the structure aligned and the
padding implicit. To wrap them, the following formula is used:
`limbs = (fieldSize div 2) + (fieldSize mod 2)`, which can be read as the
integer coefficient of half the field size, plus its remainder. This container
also happens to be preceded by a limb which contains the ID of the field, with
the basic form of every field being:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  | variable |

Furthermore, this container structure can vary depending on the classification
of the field it is wrapping, with the existing classes being:

- Padding/skip
- File termination
- Write in Progress (WIP)
- Atomic fields
- Container fields
- Bitfields
- Objects
- Variants
- Arrays

> All fields/objects/types must declare a fixed size inside the interface
description file of the ISBF dialect, as to enable concurrent writes over the
file. This doesn't apply for appending information at the end of the file, as
it is strictly sequential.

> Given that ISBF messages are restricted to a single field/object/type inside
the data section, the use of Variants and Arrays is necessary to support
multiple records being written and future appending of data.

### Padding/skip

For every empty slot or field in any of the previous types, a padding/skip
limb is added, so as to allow the parser to continue reading the next limb
until the next field is found. This limb is fully zeroed (`0`) to make
identifying it easier. It could also be said that its ID is `0x0000`.

In the case where the padding/skip limb is in the position of what would be an
ID, no matter whether the type is fixed or flexible sized, then the parser can
skip to the next field without reading the limbs within the current type, as
it is now considered empty.

> The padding/skip class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### File Termination

Even though the ISBF is aware of the file size reported by the filesystem, an
additional file termination ID (`0xFFFF`) is employed to mark the actual end
of the file, so as to prevent reading the random data that may come from a
memory allocation until it has been rewritten.

> The File Termination class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### Write in Progress (WIP)

Every time the ISBF parser is being used to create, append, or modify data
within the file, a six-step or three-step process is used to ensure that, in
the case of a crash, power outage, forced shutdown, or any other form of
system failure, the specific corrupted object/field is singled out and the
system is free to decide how to handle its recovery. This process uses the
Write in Progress (`0xFFFE`) ID to signal which element is being
written/overwritten, and its steps are the following:

- **In the case of creation/appendage (strictly sequential):**
  1. Go to the file termination limb.
  2. Allocate the necessary extra space for the new object/field and the new
     file termination limb.
  3. Write the file termination limb to the new last limb.
  4. Rewrite the previous file termination limb to a WIP ID.
  5. Write the data to the object/field.
  6. Change the WIP ID to the actual ID of the object/field.
- **In the case of modification (concurrency enabled):**
  1. Change the ID of the object/field to WIP (`0xFFFE`).
  2. Perform the desired modifications.
  3. Change the ID of the object/field back to its original value.

This also serves as a way to coordinate multiple ISBF writers, as the WIP ID
serves as a mutex/lock for the specific slot, and the lack thereof means that
the slot is free to be worked on.

> The Write in Progress class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### Atomic fields

Atomic fields remain almost identical to the basic form, with the sole
distinction over their structure being whether they are fixed or flexible
sized:

- **Structure**:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |  Fixed   |

The size in limbs of the value has already been set, and there is no need to
add further information to help with its parsing.

> Atomic fields are the only ones that don't need to declare whether the last
limb is completely used or not.

### Container fields

Container fields stand a single level above atomic fields, as they remain
largely similar, but force the use of the `Size` section regardless of whether
the field is fixed or flexible sized, and treat this section as an arbitrary
length signed integer, which indicates with its sign whether the last limb of
the value is fully used or not; negative if only the first byte is used,
positive if both bytes are used.

- **Structure**:

| **Semantic value** | ID |  Size |   Limbs  |
| ------------------ | -- | ----- | -------- |
| **Size in limbs**  | 1  | Fixed |   Fixed  |

In the case of a container, both the `Size` and the `Value` sections are fixed
size, but that doesn't mean that the last limb is going to be fully used, as
the container is the one with the fixed size, not the data it contains, hence
the need for the `Size` section.

### Bitfields

Bitfields are the first heterogeneous containers and they inherit the
properties of the atomic class. They are meant to be used to split one or
multiple limbs into heterogeneous sequences of bits, which will become
subfields for it, replicating the behavior of an object/tuple at a smaller
scale, but with the constraint of interpreting every subfield as an unsigned
integer, and each of them not being bigger than 15 bits.

- **Structure**:

| **Semantic value** | ID |   Limbs  |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |   Fixed  |

While the core value is fixed size, its bits will be split to get the
contained subfields within it. These subfields shall be defined inside the
interface description file of the respective ISBF dialect.

> Subfields carry no ID, only their value.

### Objects

Objects are essentially the same as bitfields; the only difference is that
the fields can be of any type (including other objects) and they use full
limbs instead of subsets of their bits.

It is worth noting that the fields inside an object omit their ID limb, as it
can be inferred from the order within the object. This serves as a way to
optimize storage/memory space, as fewer limbs are required for identification.

- **Structure**:

| **Semantic value** | ID | Fields (without their IDs) |
| ------------------ | -- | -------------------------- |
| **Size in limbs**  | 1  |           Fixed            |

### Variants

Variants stand at the top of the abstraction levels, and they enable the use
of different types inside the same field, constrained by a list of allowed
types, and the forced use of their ID. In this sense, they are the ISBF
equivalent to Nim's object variants.

> Variants will always be the size of their biggest allowed type.

- **Structure**:

| **Semantic value** | ID of the field type |       Field       |
| ------------------ | -------------------- | ----------------- |
| **Size in limbs**  |           1          |       Fixed       |

Variants and their allowed types are to be defined inside the interface
description file of the ISBF dialect, and to be used within the definitions of
other types to avoid having to declare each allowed combination of fields as
multiple, different types.

### Arrays

Arrays are meant to hold a list of elements of another type, so it is
impossible to make assumptions over their structure and data without knowing
the type they store first.

In this sense, the `Size` section of an array can only represent the number of
elements stored within the structure from the start, giving no information
regarding the actual amount of limbs that hold the data without knowing the
stored type first. Also, this section is interpreted as an arbitrary length
unsigned integer.

Elements inside an array keep their ID limb to be able to support changing it
to WIP, as to enable concurrent writers operating over the array.

> Unlike any of the other classes, arrays can be either fixed or flexible
sized depending on whether they are defined inside the top level object or
not.

- **Fixed size Structure (defined below the top level object)**:

| **Semantic value** | ID |  Size | Elements (with their IDs) |
| ------------------ | -- | ----- | ------------------------- |
| **Size in limbs**  | 1  | Fixed |           Fixed           |

A fixed size array has a set amount of limbs and slots to store its elements,
with its `Size` section representing the amount of used slots from the start
of the container.

- **Flexible size structure (declared inside the top level object)**:

| **Semantic value** | ID |  Size | Elements (with their IDs) |
| ------------------ | -- | ----- | ------------------------- |
| **Size in limbs**  | 1  | Fixed |         Variable          |

Flexible size arrays have a variable amount of elements, restricted to the
maximum addressable number allowed by the `Size` section, defined along with
the array.

## 6. Reserved and built-in types of the ISBF

The ISBF reserves the following IDs:

- `0x0000`: padding/skip ID
- `0xFFFE`: write in progress (WIP) ID
- `0xFFFF`: file termination ID
- `0x0001` to `0x00FF`: reserved for built-in types

Implemented from these classes and within the reserved space for built-in
types, the ISBF defines the following so developers can use them in the
definition of their own ISBF dialects:

- `0x0001` (container): ISBF dialect's interface definition
- `0x0002` (container): BLOB
- `0x0003` (container): UTF-8 string
- `0x0004` (atomic): 64-bit boolean
- `0x0005` (atomic): arbitrary length natural
- `0x0006` (atomic): arbitrary length integer
- `0x0007` (atomic): arbitrary length rational
- `0x0008` (atomic): unsigned 8-bit integer
- `0x0009` (atomic): unsigned 16-bit integer
- `0x000A` (atomic): unsigned 32-bit integer
- `0x000B` (atomic): unsigned 64-bit integer
- `0x000C` (atomic): 8-bit integer
- `0x000D` (atomic): 16-bit integer
- `0x000E` (atomic): 32-bit integer
- `0x000F` (atomic): 64-bit integer
- `0x0010` (atomic): 32-bit float
- `0x0011` (atomic): 64-bit float

For every dialect-specific type, one must use the IDs in the range `0x0100` to
`0xFFFD`.

### Regarding the arbitrary length numbers

The arbitrary length numbers (natural, integer, and rational) are meant to
have the following structures:

- **Natural:** every limb is part of the number, no metadata.
- **Integer:** the first limb is a boolean that defines the sign, the rest of
  the limbs compose the actual number.
- **Rational:** the first limb defines the sign, the rest of the limbs compose
  the number. It is assumed that the same amount of limbs used for the
  numerator is used for the denominator too.

## 7. Built-in ISBF dialect for dialect definition

To create and share new ISBF dialects, it is necessary to first create an
interface description file, which comes in the form of another ISBF file with
a predefined dialect that has as its dialect magic bytes
`[0, 0, 0, 0, 0, 0, 0, 0]` and dialect version `1`.

### 7.1 Structure of the interface definition file

The interface definition file is a valid ISBF message:

- **Header**: magic `['I','S','B','F']`, ISBF version `1`, dialect MB
  `[0,0,0,0,0,0,0,0]`, dialect version `1`.
- **Data section**: a single `0x0001` container (ISBF dialect's interface
  definition).

The `0x0001` container is a flexible-size container (its maximum size must be
declared at creation time, per the general rule for flexible-size fields). Its
payload is the dialect declaration, defined below.

### 7.2 Dialect declaration structure

The `0x0001` container's payload has the following structure. All fields use
built-in ISBF types (Section 6), so the payload can be parsed by any
ISBF-conforming reader without needing a pre-existing dialect.

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Name length        | `UInt16`      | Length of the dialect name in bytes                    |
| Name               | UTF-8 string  | Dialect name (used for MB derivation, see 7.5)         |
| Version            | `UInt16`      | Dialect major version (matches header's dialect version) |
| Type count         | `UInt32`      | Number of type declarations                            |
| Type declarations  | `Array` of `TypeDeclaration` | Type declarations, in declaration order |

### 7.3 Type declaration structure

Each type declaration is an `Object` with the following fields:

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Type ID            | `UInt16`      | The type's assigned ID (must be in `0x0100`–`0xFFFD`) |
| Class              | `UInt8`       | `0x01`=bitfield, `0x02`=object, `0x03`=variant, `0x04`=array |
| Name length        | `UInt16`      | Length of the type's name in bytes                     |
| Name               | UTF-8 string  | Type name (for documentation and diagnostics)          |
| Class payload      | varies        | Class-specific declaration (see 7.3.1–7.3.4)           |

#### 7.3.1 Bitfield declaration (`0x01`)

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Subfield count     | `UInt8`       | Number of subfields                                    |
| Subfields          | `Array` of `Subfield` | Subfield declarations, in declaration order |

Each `Subfield`:

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Name length        | `UInt16`      | Length of the subfield's name                          |
| Name               | UTF-8 string  | Subfield name                                          |
| Width              | `UInt8`       | Width in bits (must be ≤ 15)                           |
| Constraint count   | `UInt8`       | Number of constraints                                  |
| Constraints        | `Array` of `Constraint` | Constraints on this subfield's value         |

#### 7.3.2 Object declaration (`0x02`)

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Field count        | `UInt8`       | Number of fields                                       |
| Fields             | `Array` of `ObjectField` | Field declarations, in declaration order    |

Each `ObjectField`:

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Type ID            | `UInt16`      | Reference to a type (built-in or dialect-declared)     |
| Name length        | `UInt16`      | Length of the field's name                             |
| Name               | UTF-8 string  | Field name                                             |
| Constraint count   | `UInt8`       | Number of constraints                                  |
| Constraints        | `Array` of `Constraint` | Constraints on this field's value            |

#### 7.3.3 Variant declaration (`0x03`)

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Allowed count      | `UInt8`       | Number of allowed type alternatives                    |
| Allowed type IDs   | `Array` of `UInt16` | Type IDs of the allowed alternatives (max size of the variant is the largest among them) |

#### 7.3.4 Array declaration (`0x04`)

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Element type ID    | `UInt16`      | Reference to the element's type                        |
| Maximum elements   | `UInt32`      | Maximum number of elements the array can hold          |

### 7.4 Constraint structure

A constraint declares a semantic restriction on a field's value. Its structure
depends on the constraint type.

| Field              | Type          | Description                                            |
| ------------------ | ------------- | ------------------------------------------------------ |
| Constraint type    | `UInt8`       | See the constraint type table below                    |
| Constraint value   | varies        | Encoded per the constraint type and the constrained field's type |

| Code | Name                | Applies to          | Value encoding                          |
| ---- | ------------------- | ------------------- | --------------------------------------- |
| `0x01` | Minimum value     | Numeric types       | The field's own wire format             |
| `0x02` | Maximum value     | Numeric types       | The field's own wire format             |
| `0x03` | Multiple of       | Numeric types       | The field's own wire format             |
| `0x04` | Odd               | Integer types       | None (no value follows)                 |
| `0x05` | Even              | Integer types       | None (no value follows)                 |
| `0x06` | Minimum size      | `BLOB`, `String`    | `UInt32`                                |
| `0x07` | Maximum size      | `BLOB`, `String`    | `UInt32`                                |
| `0x08` | Size multiple of  | `BLOB`, `String`    | `UInt32`                                |
| `0x09` | Allowed UTF-8 ranges | `String`         | `Array` of `{Start: UInt32, End: UInt32}` |

The `Allowed UTF-8 ranges` constraint carries an array of up to 64 ranges.
Each range declares an inclusive code-point interval `[Start, End]`; a string
whose code points all fall within the union of the declared ranges is
considered valid.

The `Minimum value`, `Maximum value`, and `Multiple of` constraints on
arbitrary-precision types (`Natural`, `Integer`, `Rational`) are encoded using
the same wire format as the constrained field itself. The `Amount of limbs`
constraint described in Section 7.6 below is encoded as `UInt16` and applies
only to `Natural`, `Integer`, and `Rational`.

### 7.5 Dialect magic bytes derivation

The dialect magic bytes are derived from the dialect name declared in 7.2:

1. Encode the name as UTF-8 bytes.
2. Compute SHA-256 over those bytes.
3. Take the first 8 bytes of the digest.

The result is the 8-byte dialect magic bytes that appear in the header (see
Section 4). The interface-definition dialect itself uses the sentinel
`[0,0,0,0,0,0,0,0]`, which cannot result from any valid name because a real
SHA-256 truncation to 8 bytes has a 1-in-2^64 chance of being all zeros, and
the sentinel is explicitly reserved.

### 7.6 Permitted constraints per built-in type

Constraints may only be applied to built-in types (IDs `0x0002`–`0x0011`).
They cannot be applied to dialect-declared types directly; they must be
applied at the point of use (in the field declaration of an object) or, for
bitfields, at the subfield declaration. The following constraints are
supported per type:

- **`0x0002` (BLOB)**: minimum size, maximum size (required), size multiple
  of.
- **`0x0003` (UTF-8 string)**: minimum size, maximum size (required), size
  multiple of, allowed UTF-8 ranges (up to 64 ranges).
- **`0x0004` (64-bit boolean)**: no constraints.
- **`0x0005` (Natural)**: amount of limbs (required), minimum value, maximum
  value, multiple of, odd, even.
- **`0x0006` (Integer)**: amount of limbs (required), minimum value, maximum
  value, multiple of, odd, even.
- **`0x0007` (Rational)**: amount of limbs (required), minimum value, maximum
  value, multiple of, odd, even.
- **`0x0008`–`0x0011` (fixed-width integers and floats)**: minimum value,
  maximum value, multiple of, odd (integer types only), even (integer types
  only).

The `Amount of limbs` constraint is required for `Natural`, `Integer`, and
`Rational`, because without it the field's slot size would not be fixed. For
fixed-width types (`0x0008`–`0x0011`), the slot size is implicit in the type
ID and no length constraint is needed.

### 7.7 Type references and forward declarations

Types may reference other types by ID. A type declaration may reference a type
that is declared later in the same file (forward reference). The parser must
collect all type declarations before resolving references, so that the
declaration order does not matter.

A type declaration may reference a built-in type (ID in `0x0002`–`0x0011`) or
a dialect-declared type (ID in `0x0100`–`0xFFFD`). It may not reference a type
in the reserved ranges (`0x0000`, `0x0001`, `0xFFFE`, `0xFFFF`), nor may it
reference itself recursively (recursive types are prohibited — see Section 9).

### 7.8 Example (informational)

A minimal dialect declaring a `Person` object with two fields (`name` of type
UTF-8 string, `age` of type UInt8) would, after the header, contain a `0x0001`
container whose payload declares:

- Name: `io.intrashell.example.person`
- Version: `1`
- Type count: `1`
- Type declaration: ID `0x0100`, class `0x02` (object), name `Person`,
  two fields:
  - Field 1: type `0x0003` (String), name `name`, max size `64`
  - Field 2: type `0x0008` (UInt8), name `age`, max value `255`

The dialect MB for this file would be the first 8 bytes of
`SHA-256("io.intrashell.example.person")`.

## 8. Error handling and trace events

The ISBF parser communicates its state through a set of 8-bit codes. These
codes fall into four categories, distinguished by what they report and by what
the parser does when it emits one.

### 8.1 Categories

1. **Success** (`0x01`): the terminal state after a successful parse. Not an
   event per se; it is the return value when nothing failed.
2. **Trace events** (`0x02`–`0x24` subset): informational events describing
   what the parser is doing. Trace events do not affect parsing; they are
   emitted when tracing is enabled and are otherwise suppressed. They are
   never returned as errors.
3. **Hard errors**: parse failures that prevent further parsing. The parser
   must stop immediately. These are always returned.
4. **Parseable errors** (also called *soft errors*): parse failures that allow
   the parser to continue. The application may inspect the partially-parsed
   result and decide whether to abort, log, or recover.

The distinction matters because a trace event and a parseable error can appear
in the same parser run (e.g., "found atomic field" is a trace event, "atomic
value invalid" is a parseable error), whereas a hard error terminates the run
immediately.

### 8.2 Success

| Error code | Error name | Category |
| ---------- | ---------- | -------- |
|   `0x01`   |     Ok     | Success  |

### 8.3 Trace events

These codes report that the parser has encountered a valid structure. They are
emitted only when tracing is enabled, and they never affect the parse result.

| Error code |              Error name              | Category |
| ---------- | ------------------------------------ | -------- |
|   `0x02`   |             Found header             | Trace    |
|   `0x04`   |     Supported ISBF version found     | Trace    |
|   `0x07`   |        Found embedded dialect        | Trace    |
|   `0x0A`   |            Dialect valid             | Trace    |
|   `0x0C`   |          Found atomic field          | Trace    |
|   `0x0D`   |     Atomic field's value is valid    | Trace    |
|   `0x0F`   |         Found container field        | Trace    |
|   `0x10`   |    Container field's size is valid   | Trace    |
|   `0x12`   |         Found bitfield field         | Trace    |
|   `0x13`   |       Found bitfield's subfield      | Trace    |
|   `0x14`   |  Bitfield's subfield value is valid  | Trace    |
|   `0x16`   |          Found object field          | Trace    |
|   `0x17`   |          Found variant field         | Trace    |
|   `0x18`   |   Variant field's value/ID is valid  | Trace    |
|   `0x1A`   |          Found array field           | Trace    |
|   `0x1B`   |     Array field's size is valid      | Trace    |
|   `0x1D`   |       Found padding/skip field       | Trace    |
|   `0x1F`   |     Found file termination field     | Trace    |

### 8.4 Hard errors

These codes report failures that prevent further parsing. The parser must
stop immediately and return the code to the caller.

| Error code |              Error name              | Category  |
| ---------- | ------------------------------------ | --------- |
|   `0x03`   |           Header not found           | Hard      |
|   `0x05`   |    Unsupported ISBF version found    | Hard      |
|   `0x08`   |       Invalid embedded dialect       | Hard      |
|   `0x09`   |  Dialect beyond size constraint      | Hard      |
|   `0x0B`   |           Dialect invalid            | Hard      |
|   `0x24`   |  File is beyond the size constraint  | Hard      |

### 8.5 Parseable errors

These codes report failures that permit continued parsing. The application may
inspect the partially-parsed result and decide how to proceed. The parser
should not silently discard these; it must surface them so the application can
react.

| Error code |              Error name              | Category  |
| ---------- | ------------------------------------ | --------- |
|   `0x06`   |      Unrecognized dialect's MB       | Parseable |
|   `0x0E`   |    Atomic field's value is invalid   | Parseable |
|   `0x11`   |  Container field's size is invalid   | Parseable |
|   `0x15`   | Bitfield's subfield value is invalid | Parseable |
|   `0x19`   | Variant field's value/ID is invalid  | Parseable |
|   `0x1C`   |    Array field's size is invalid     | Parseable |
|   `0x1E`   |  Found padding/skip at an ID limb    | Parseable |
|   `0x20`   | Found file termination prematurely   | Parseable |
|   `0x21`   |          Found WIP field             | Parseable |
|   `0x22`   |        Unrecognized ID               | Parseable |
|   `0x23`   |    Couldn't allocate more space      | Parseable |

### 8.6 Notes on numbering stability

Error code assignments are stable across ISBF revisions. New codes may be
introduced in `0x25` and above; existing codes will not be reassigned.
Implementations may add codes above `0x80` for their own diagnostics, provided
those codes are clearly documented as implementation-specific.

## 9. Security

To ensure security while parsing ISBF files, the parser should consider the
following cases.

### Integer overflow in the size section of fields

Parsers should reject ISBF messages that have fields whose `Size` section is
above the bounds of the field. This applies to all classes.

Whenever a field, no matter the class, has a `Size` section whose value is
beyond its bounds, the ISBF parser should emit the pertinent "size is invalid"
error code:

- `0x11`: for containers
- `0x1C`: for arrays

### Recursive objects in dialect definitions

Parsers should reject dialect definitions that have fields at the same
taxonomical level nesting each other. Fields should always be either parent,
children, or adjacent to other fields; they should never fulfill more than one
role.

For these cases, depending on the context, the ISBF parser should output any
of the following error codes:

- `0x08`: for embedded dialects
- `0x0B`: for pre-shared dialects

### Potential magic bytes collision for dialects

Given that the magic bytes for the ISBF dialect are automatically generated
from strings longer than 64 bits by truncating their SHA-256 hash, one must
account for the potential case in which two dialects end up sharing the same
magic bytes, as this could lead to a malicious packet rewriting the ISBF
dialect's definition.

Parsers should offer these options for reading ISBF files:

- Open file with a pre-shared dialect and ignore any embedded dialects
  (default).
- Open file and parse with the embedded dialect (if present).
- Open file and ignore any dialect definition (for inspection).

### Embedded interface definition size limit

ISBF parsers should allow developers to define a size limit for parsing
embedded dialects, which by default should be 1 MB.

### Use of file termination limb on variant fields

ISBF parsers should not allow writing the file termination inside the list of
allowed values for a variant field. In the same vein, parsers should emit the
`0x20` error code if they happen to find it within a variant field.

## 10. Notes

### About the versioning of ISBF and its dialects

As formats are not intended to be updated with the same frequency as a program
would, there is no need to implement full semantic versioning for them, so the
versioning format used is `Major.Revision`, where the "Major" indicates the
actual format being used, and the revision is left for the version of the
document that describes it. This also means that only the "Major" version is
relevant for ISBF parsers, and therefore is the only one used within the ISBF
header.

### About the design of the interface description dialects

The ISBF was born out of the necessity to share a common format for data
stores and communications protocols, and as those two diverge in design once
the paging/block allocation/framing is done, then the best way to serve both
was to target this very same layer, so the ISBF became a block-level metaformat
abstraction to enable developers to write their own dialects and solutions to
achieve the specific design for their needs. In this sense, the ISBF is:

- A block allocator for files and packets: the ISBF is meant to reason about
  whole blocks of memory, not single fields like a scratch allocator may do.
- Below SQLite as an abstraction: SQLite provides paging, B-Trees, and an
  internal metadata table that tracks records and unallocated slots across the
  pages. The ISBF provides only the paging, and leaves the developer to choose
  the paradigms and techniques to build the layers above, whether they be
  LSM-Trees, SST, shadow paging, WAL, rollback journals, or a combination of
  such.
- Above ASN.1 as an abstraction: ASN.1 cares only about the specific encoding
  of data structures; in contrast, the ISBF provides said data structures by
  default and allows you to skip straight to defining how they are laid out on
  a packet, which are their semantic constraints, and which are the message
  shapes.

This means that the ISBF enables you to build your own databases, data
stores, filesystems, application formats, and communication protocols from
first principles, without reinventing block allocation, page recovery, or
endianness handling, while leaving every architectural choice above the block
layer to you. Therefore it is not a replacement for systems like SQLite,
ASN.1, CBOR, Thrift, or Avro, which provide abstractions above the block
layer; WAL, shadow paging, SSTs, and LSM-Trees are above the block layer and
must be built on top of the ISBF, not provided by it.

### Ensuring support for write concurrency

While the WIP ID can signal that a specific slot is currently being written
to, it is not an atomic value that the CPU can access in nanoseconds, so an
additional, lock-free structure must be implemented in the parser to track
which slots have been locked by other threads/processes. This way, multiple
I/O tasks can be performed without risk.

One way to implement this is to use a lock-free circular list that tracks the
currently-being-written slots.

Also, appending operations should be strictly sequential, and the ISBF writer
should enforce this, either by implementing a lock or using any other method
that it sees fit for the task.

### About ACID support

While the ISBF provides built-in features to handle data corruption and write
concurrency, it doesn't support atomicity, consistency, isolation, nor
durability, as those features can only be fully supported if the specific
dialect provides ways to ensure them. For that, the dialect would have to, for
example, provide:

- An internal metadata table to reference the current records.
- An internal WIP type to append the new version of the records.
- An update/modification mechanism to change the references in the metadata
  table from the current records to the updated ones.

Of course, alternative ways may be used, but the underlying principle remains
the same: ACID support needs to be contemplated in the ISBF dialect and the
system that parses it.
