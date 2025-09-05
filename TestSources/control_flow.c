int main(void) {
    int x = 3 + 4;
    x *= 15;
    x = x + 100;
    int y = x > 400 ? 399 : 401;
    if (x < 255) {
        return x;
    } else {
        return 5;
    }
}