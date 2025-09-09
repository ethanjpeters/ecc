int main(void) {
    int x = 15;

    for (int y = 0; y < 12; y++) {
        int z = 3;
        x = (x + y) % 3;
        if (x == 12) { break; }
        if (x == 13) { continue; }
    }

    for (;;) {
        x += 1;
        break;
    }

    while (1) {
        x++;
        if (x > 100) {
            break;
        }
    }

    do {
        x = x - 8;
    } while (x > 100);

    return x;
}