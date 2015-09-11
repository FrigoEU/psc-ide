psc-ide
===

A tool which provides editor support for the PureScript language.

[![Build Status](https://travis-ci.org/kRITZCREEK/psc-ide.svg?branch=travis-build)](https://travis-ci.org/kRITZCREEK/psc-ide)

## Editor Integration
* [@epost](https://github.com/epost) wrote a plugin to integrate psc-ide with Emacs at https://github.com/epost/psc-ide-emacs.
* Atom integration is available with https://github.com/nwolverson/atom-ide-purescript.

## Running the Server
Start the server by running the `psc-ide-server` executable.
It supports the following options:

- `-p / --port` specify a port. Defaults to 4242
- `-d / --directory` specify the toplevel directory of your project. Defaults to
  the current directory

## Issuing queries

After you started the server you can start issuing requests using psc-ide.
Make sure you start by loading the modules before you try to query them.

psc-ide expects the build externs.purs inside the `output/` folder of your
project after running `pulp build` or `psc-make` respectively.

(If you changed the port of the server you can change the port for psc-ide by
using the -p option accordingly)

## Protocol

For a documentation have a look at:
[PROTOCOL.md](PROTOCOL.md)

## Installing and Building

The project is set up to be built using the
[stack](https://github.com/commercialhaskell/stack) tool.

```bash
cd psc-ide
stack setup # This is only required if you haven't installed GHC 7.10.2 before
stack build # add --copy-bins to also copy the compiled binaries to ~/.local/bin/
stack exec -- psc-ide-server &
stack exec -- psc-ide
```

## Testing

The testsuite can be run with `stack test`.
If you make changes to the tests stack won't notice them so you need to
do `stack clean && stack install` to rebuild the tests. 


