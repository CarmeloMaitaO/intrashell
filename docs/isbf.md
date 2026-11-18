# IntraShell Binary Format (ISBF) especification V1.0

## 0. Conformance

ISBF readers and writers should accept previous versions of the specification,
but should reject future revisions of the supported versions of the
specification to prevent data corruption.

## 1. Overview

The ISBF is a self-describing, semantically constrained, schema-driven format
optimized for block allocation and concurrent I/O by default; intended to be
used to define, parse and write new file/application formats and communication
protocols.

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
parsed; a single field/object from the ISBF dialect is expected, with an
optional, preceding embedded interface definition of said dialect, so the
schema can be recovered from the file itself. This provides a way to preserve
the readability of files across time, even if the original interface description
is lost in the future.

## 5. Basic wrapper container and data fields/objects

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

Furthermore, this container structure can vary depending on the classification
of the field it's wrapping, with the existing classes being:

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
file. This doesn't apply for appending information at the end of the file, as it
is strictly sequential.

> Given that ISBF messages are restricted to a single
field/object/type inside the data section, the use of Variants and Arrays is
necessary to support multiple records being written and future appending of
data.

### Padding/skip

For every empty slot or field in any of the previous type, a padding/skip limb
is added, as to allow the parser to continue reading the next limb until the
next field is found. This limb is fully zeroed (`0`) to make identifying it
easier. It could also be said that it's ID is `0x0000`.

In the case the Padding/skip limb is in the position of what would be an ID,
no matter if the type is fixed or flexible sized, then the parser can skip
to the next field without reading the limbs within the current type, as it is
considered now empty.

> The padding/skip class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### File Termination

Even though the ISBF is aware of the file size reported by the filesystem, an
additional file termination ID (`0xFFFF`) is employed to mark the actual end of
the file, as to prevent reading the ramdom data that may come from a memory
allocation until it has been rewritten.

> The File Termination class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### Write in Progress (WIP)

Every time the ISBF parser is being used to create, append or modify data within
the file, a five or three steps process is used to ensure that, in the case of
a crash, power outage, forced shutdown or any other form of system failure, the
specific corrupted object/field is singled out and the system is free to decide
how to handle it's recovery. This process uses the Write in Progress (`0xFFFE`)
ID to signal which element is being written/overwritten, and it's steps are
the following:

- **In the case of creation/appendage (strictly sequential):**
  1. Go to the file termination limb
  2. Allocate the necessary extra space for the new object/field and the new
  file termination limb
  3. Write the file termination limb to the new last limb
  4. Rewrite the previous file termination limb to a WIP ID.
  4. Write the data to the object/field
  5. Change the WIP ID to the actual ID of the object/field
- **In the case of modification (concurrency enabled):**
  1. Change the ID of the object/field to WIP (`0xFFFF`)
  2. Perform the desired modifications
  3. Change the ID of the object/field back to it's original value

This also serves as a way to coordinate multiple ISBF writers, as the WIP ID
serves as a mutex/lock for the specific slot, and the lack thereof means that
the slot is free to be worked on.

> The Write in Progress class is considered a specific type, and therefore the
declaration of other fields based on this type is not supported in the
interface definition file of any ISBF dialect.

### Atomic fields

Atomic fields remain almost identical to the basic form, with the sole
distinction over their structure being whether they are fixed or flexible sized:

- **Structure**:

| **Semantic value** | ID |  Value   |
| ------------------ | -- | -------- |
| **Size in limbs**  | 1  |  Fixed   |

The size in limbs of the value has already been set, and there's no need to add
further information to help with it's parsing.

> Atomic fields are the only ones that don't need to declare if the last limb
is completely used or not.

### Container fields

Container fields stand a single level above atomic fields, as they remain
largely similar, but forces the use of the `Size` section regardless of whether
the field is fixed or flexible sized, and treats this section as an arbitrary
length signed integer, which indicates with it's sign whether the last limb of
the value is fully used or not; negative if only the first byte is used,
positive if both bytes are used.

- **Structure**:

| **Semantic value** | ID |  Size |   Limbs  |
| ------------------ | -- | ----- | -------- |
| **Size in limbs**  | 1  | Fixed |   Fixed  |

In the case of a container, both the `Size` and the `Value` sections are fixed
size, but that doesn't mean that the last limb is going to be fully used, as the
container is the one with the fixed size, not the data it contains, hence the
need for the `Size` section.

### Bitfields

Bitfields are the firsts heterogeneous containers and they inherit the
properties of the atomic class. They are meant to be used to split one or
multiple limbs into heterogeneous sequences of bits, which will become subfields
for it, replicating the behaviour of an object/tuple at a smaller scale, but
with the constraint of interpreting every subfield as an unsigned integer, and
each of them not being bigger than 15 bits.

- **Structure**:

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
instead of subsets of their bits.

It is worth noting that the fields inside an object omit their ID limb, as it
can be inferred from the order within the object. This serves as a way to
optimize storage/memory space, as less limbs are required for identification.

- **Structure**:

| **Semantic value** | ID | Fields (without their IDs) |
| ------------------ | -- | -------------------------- |
| **Size in limbs**  | 1  |           Fixed            |

### Variants

Variants stand at the top of the abstraction levels, and they enable the use of
different types inside the same field, constrained by a list of allowed types,
and the forced use of its ID. In this sense, they are the ISBF equivalent to
Nim's object variants.

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

Arrays are meant to hold a list of elements of another type, so it's impossible
to make assumptions over it's structure and data without knowing the type it
stores first.

In this sense, the `Size` section of an array can only represent the number of
elements stored within the structure from the start, giving no information
regarding the actual amount of limbs that hold the data without knowing the
stored type first. Also, this section is interpreted as an arbitrary length
unsigned integer.

Elements inside an array keep their ID limb to be able to support changing it
to WIP, as to enable concurrent writers operating over the array.

> Unlike any of the other classes, arrays can be either fixed or flexible sized
depending on whether they are defined inside the top level object or not.

- **Fixed size Structure (defined below the top level object)**:

| **Semantic value** | ID |  Size | Elements (with their IDs) |
| ------------------ | -- | ----- | ------------------------- |
| **Size in limbs**  | 1  | Fixed |           Fixed           |

A fixed size array has a set amount of limbs and slots to store its elements,
with its `Size` section representing the amount of used slots from the start of
the container.

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

Implemented from these classes and within the reserved space for built-in types,
the ISBF defines the following so developer can use in the definition of their
own ISBF dialects:

- `0x0001` (container): ISBF dialect's interface definition
- `0x0002` (container): BLOB
- `0x0003` (container): UTF-8 string
- `0x0004` (atomic): boolean
- `0x0005` (atomic): Natural
- `0x0006` (atomic): Integer
- `0x0007` (atomic): Rational

For every dialect specific type, one must use the IDs in the range `0x0100`,
`0xFFFD`.

## 7. Built-in ISBF dialect for dialect definition

To create and share new ISBF dialects it is necessary to first create an
interface definition file, which comes in the form of another ISBF file with
a predefined dialect, which has as the dialect's magic bytes
`[0, 0, 0, 0, 0, 0, 0, 0]`.

Within this definition file, it is only possible to declare new types and their
semantic constraints based on the following ISBF classes:

- Bitfields: defines subfields length and constraints to their values.
- Objects: defines inner fields and constraints to their values.
- Variants: define lists of allowed types.
- Arrays: defines contained type and maximum amount of contained elements.

Definitions extending these classes will generate new IDs and contain either
built-in ISBF types or other defined types inside the dialect.

The available semantic constraints are limited to the built-in types, and
new costraint definitions, just like new definitions based on atomic and
container classes, are not support. The supported constraints are:

- `0x0002` (BLOB):
  - Minimum size
  - Maximum size (required)
  - Size as multiple of
- `0x0003` (UTF-8 string):
  - Minimum size
  - Maximum size (required)
  - Size as multiple of
  - Allowed values (array of 64 ranges of allowed UTF-8 code points)
- `0x0005` (natural):
  - Amount of limbs (required)
  - Minimum value
  - Maximum value
  - Value as multiple of
  - Value as odd number
  - Value as even number
  - Value as prime
- `0x0006` (integer):
  - Amount of limbs (required)
  - Minimum value
  - Maximum value
  - Value as multiple of
  - Value as odd number
  - Value as even number
  - Value as prime
- `0x0007` (rational): 
  - Amount of limbs (required)
  - Minimum value
  - Maximum value
  - Value as multiple of
  - Value as odd number
  - Value as even number
  - Value as prime

## 8. Error handling

## 9. Security

To ensure security while parsing ISBF files, the parser should consider these
cases:

### Integer overflow in the size section of fields

Parsers should reject ISBF messages that have fields whose `Size` section is
above the the bounds of the field. This applies to all classes.

### Recursive objects in dialect definitions

Parsers should reject dialect definitions that have fields at the same
taxonomical level nest each other. Fields should always be either parent,
children or adjacent to other fields, they should never fullfill more than one
role.

### Potencial magic bytes collusion for dialects

Given that the magic bytes for the ISBF dialect are automatically generated from
strings longer that 64 bits, by truncating a SHA-256 hash, then one must account
for the potencial case in which two dialects end up sharing the same magic
bytes, as this could lead to a malicious packet rewritting the ISBF dialect's
definition.

- Parsers should offer these options for reading ISBF files:
  - Open file with a pre-shared dialect and ignore any embedded dialects
  (default)
  - Open file and parse with the embedded dialect (if present)

## 10. Notes

### About the versioning of ISBF and it's dialects

As formats are not intended to be updated with the same frequency a program
would, there's no need to implement full semantic versioning for them, so the
versioning format used is `Major.Revision`, where the "Major" indicates the
actual format being used, and the revision is left for the version of the
document that describes it. This also means that only the "Major" version is
relevant for ISBF parsers, and therefore is the only one used within the
ISBF header.

### About the design of the interface description dialects

The ISBF is intended to allow developers to be fully aware of how data is going to
end up layed out in disk, as to enable them to build more complex systems like
databases on top of it, which is why the design ended up oriented for block
allocation and a single allowed field/object, forcing the use of arrays and
variants for enabling appending information to files, as to force the developer
to choose a paging strategy, effectively forcing them to declare a paging
system from which they will write their data store or protocol.

The ISBF was made to provide a ready-made solution for building binary formats
for disk/memory storage and communication protocols, and while it abstract
things like endianness, binary alignment, object/message definition and
validation, it doesn't abstract the layout definition above block allocation,
and this decision was made in order to contemplate:

- **The ISBF for disk storage:**

The ISBF, when used for long-term storage, is intended to speed up the
development of a block/page allocation oriented solution, not what would
usually be implemented on top of it. This way, developers have full control of
how their data is going to be manipulated and placed within the files, enabling
them to build more complex storage systems like databases while keeping the
freedom to choose their preferred paradigms/methods/techniques (rollback
journal, WAL, shadow paging, SST, LSM-Trees, etc...).

At the same time, if the developer have no need to implement such complex
systems, and just want a way to store fixed data like in a configuration file or
a save file for a game, then they can enjoy the simplicity of the system and
declare a single, semantically constrained object, which will even save them
the effort of having to write an input sanitization phase.

- **The ISBF for communication protocols:**

The ISBF, when used to define communication protocols, is intended to save the
developer the effort of having to write a binary parser or every iteration over
the protocol and it's format, while remaining lean enough to be usable even
within a 512 bytes frame limit and constrained computing environments; paired up
with semantic validation, makes contract enforcement for clients and servers
automatic.

### Ensuring support for write concurrency

While the WIP ID can signal that a specific slot is currently being written
to, it is not an atomic value that the CPU can access in nanoseconds, so an
additional, lock-free, structure must be implemented in the parser to track
which slots have been locked by other threads/processes. This way, multiple
I/O tasks can be performed without risk.

One way to implement this is to use a lock-free circular list that tracks the
currently being written slots.

### About ACID support

While the ISBF provides built-in features to handle data corruption and write
concurrency, it doesn't support atomicity, consistency, isolation nor
durability; as those features can only be fully supported if the specific
dialect provides ways to ensure them; for that, the dialect would have to,
for example, provide:

- An internal metadata table to reference the current records
- An internal WIP type to append the new version of the records
- An update/modification mechanism to change the references in the metadata
table from the current records to the updated ones

Of course, alternative ways may be used, but the underlying principle remains
the same: ACID support needs to be contemplated in the ISBF dialect and the
system that parses it.
