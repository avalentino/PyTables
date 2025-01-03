# This script compares reading from an array in a loop using the
# tables.Array.read method.  In the first case, read is used without supplying
# an 'out' argument, which causes a new output buffer to be pre-allocated
# with each call.  In the second case, the buffer is created once, and then
# reused.

from time import perf_counter as clock

import numpy as np

import tables as tb


def create_file(array_size):
    array = np.ones(array_size, dtype="i8")
    with tb.open_file("test.h5", "w") as fobj:
        array = fobj.create_array("/", "test", array)
        print(f"file created, size: {array.size_on_disk / 1e6} MB")


def standard_read(array_size):
    n = 10
    with tb.open_file("test.h5", "r") as fobj:
        array = fobj.get_node("/", "test")
        start = clock()
        for i in range(n):
            output = array.read(0, array_size, 1)
        end = clock()
        assert np.all(output == 1)
        print(f"standard read   \t {(end - start) / n:5.5f}")


def pre_allocated_read(array_size):
    n = 10
    with tb.open_file("test.h5", "r") as fobj:
        array = fobj.get_node("/", "test")
        start = clock()
        output = np.empty(array_size, "i8")
        for i in range(n):
            array.read(0, array_size, 1, out=output)
        end = clock()
        assert np.all(output == 1)
        print(f"pre-allocated read\t {(end - start) / n:5.5f}")


if __name__ == "__main__":

    array_num_bytes = [10**5, 10**6, 10**7, 10**8]

    for array_bytes in array_num_bytes:

        array_size = array_bytes // 8

        create_file(array_size)
        standard_read(array_size)
        pre_allocated_read(array_size)
        print()
