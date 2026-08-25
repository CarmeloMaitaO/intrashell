This is a collection of things that I'm currently considering for the next major
release of Intrashell.

- Adding additional `dispatchBoilerplate` templates for executing top-level
  statements with:
  - Asynchronous procedures
  - Threads
- Modify `dispatchBoilerplate` to include automatically a variable that stores
  the pointer to the `Intrashell` object
- Adding support for multiple datatypes in the `Buffer` structure, as to
  simplify input sanitization and API design
- Adding more `IntrashellOperation` types:
  - `LOADFOLDER`: loads every module within the given folder
  - `UNLOADALL`: unloads all modules of registry, with the exception of the
    ones that were given as parameters
- Adding additional versions of the `shell()` interface:
  - An asynchronous version
  - (For modules only) a version that automatically calls the Intrashell pointer
