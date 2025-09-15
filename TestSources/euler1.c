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

int main(void) {

    int sum = 0;

    for (int i = 1; i < 1000; i++) {
        if (0 == i % 3 || 0 == i % 5) {
            sum = sum + i;
        }
    }

    putInteger(sum);

    return 0;
}