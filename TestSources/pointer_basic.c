int main(void) {
    int x = 12;
    int *ptr = &x;
    (*ptr)++;
    // *ptr = *ptr + 1;
    return x;
}