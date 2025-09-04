#!/bin/bash

swift run ecc TestSources/return_2.c
./return_2
if [[ $? -ne 2 ]]; then
    echo "return_2: Expected exit code 2 but got $?"
    exit 1
else
    echo "return_2: success"
fi
rm return_2

swift run ecc TestSources/return_math.c
./return_math
if [[ $? -ne 10 ]]; then
    echo "return_math: Expected exit code 10 but got $?"
    exit 1
else
    echo "return_math: success"
fi
rm return_math

swift run ecc TestSources/return_math_2.c
./return_math_2
if [[ $? -ne 12 ]]; then
    echo "return_math_2: Expected exit code 12 but got $?"
    exit 1
else
    echo "return_math_2: success"
fi
rm return_math_2

swift run ecc TestSources/return_not_2.c
./return_not_2
if [[ $? -ne 1 ]]; then
    echo "return_not_2: Expected exit code 1 but got $?"
    exit 1
else
    echo "return_not_2: success"
fi
rm return_not_2

swift run ecc TestSources/bitwise_ops.c
./bitwise_ops
if [[ $? -ne 7 ]]; then
    echo "bitwise_ops: Expected exit code 7 but got $?"
    exit 1
else
    echo "bitwise_ops: success"
fi
rm bitwise_ops