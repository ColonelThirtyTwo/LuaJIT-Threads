LuaJIT Threads
==============

A library for LuaJIT to spawn separate threads that run Lua code.

The library uses LuaJIT's FFI as much as it can, however some C
code it neccessary to start the thread's main function.

Files are:
 * threads.lua: The main library file. Contains primitive types such as Threads and mutexes
 * luajitthreads.c: A small bit of neccessary C code.
 * test.lua: Test code
