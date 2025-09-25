int putchar(int c); // defined in the standard library

long reverseInteger(long r) {
    long out = 0;
    while (r > 0) {
        out = (out * 10) + (r % 10);
        r = r / 10;
    }

    return out;
}

void putInteger(long i) {
    i = reverseInteger(i);
    if (i == 0) {
        putchar(48);
        return;
    }

    while (i > 0) {
        long rem = i % 10;
        putchar((int)(rem + 48));
        i = i / 10;
    }
}

int isPrime(long i) {
    for (long j = 2; j < (i/2)+1; j++) {
        if (i % j == 0) {
            return 0;
        }
    }
    return 1;
}

int main(void) {
    // long numberToFactorize = 600851475143;
    long numberToFactorize = 13195;

    long maxFactor = 0;

    for (long i = 2; i < (numberToFactorize/2)+1; i++) {
        if (numberToFactorize % i == 0 && isPrime(i)) {
            putInteger(i);
            putchar(10);
            if (i > maxFactor) { maxFactor = i; }
        }
    }
    return maxFactor;
}