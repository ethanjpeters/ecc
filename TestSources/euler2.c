int putchar(int c); // defined in the standard library

int reverseInteger(int r) {
    int out = 0;
    while (r > 0) {
        out = (out * 10) + (r % 10);
        r = r / 10;
    }

    return out;
}

void putInteger(int i) {
    i = reverseInteger(i);
    if (i == 0) {
        putchar(48);
        return;
    }

    while (i > 0) {
        int rem = i % 10;
        putchar(rem + 48);
        i = i / 10;
    }
}

int fib(int n) {
    if (n == 0) { return 0; }
    if (n == 1 || n == 2) { return 1; }

    return fib(n - 1) + fib(n - 2);
}

int main(void) {

    int sum = 0;

    for (int n = 1; ; n++) {
        int f = fib(n);
        if (f > 4000000) { break; }

        if (0 == f % 2) { sum = sum + f; }
    }

    putInteger(sum);

    return 0;
}