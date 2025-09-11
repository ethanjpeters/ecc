int main(void) {
    
    int x = 15;

    switch (x) {
        case 10: x++;
        case 15: x++;
        case 20: { x++; break; }
        case 25: x++;
        default:
            break;
    }

    int count = 100;
    int n = (count + 7) / 8;
    switch (count % 8) {
    case 0: x++;
    case 7:      x++;
    case 6:      x++;
    case 5:      x++;
    case 4:      x++;
    case 3:      x++;
    case 2:      x++;
    case 1:      x++;
    }
    return x;
}

// case 0: do { x++;
//     case 7:      x++;
//     case 6:      x++;
//     case 5:      x++;
//     case 4:      x++;
//     case 3:      x++;
//     case 2:      x++;
//     case 1:      x++;
//             } while (--n > 0);