int main(void) {
    int x = 3 > 5 ? 10 : 11;
    int y = 5 / 6;
    y += 4;
    if (x > y) {
        int z;
        z = 8 + 4;
        x = x + y + z;
    } else {
        return 1;
    }
    return x;
}