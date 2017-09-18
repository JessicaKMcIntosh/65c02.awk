/* Small program for doing non-blocking IO. */
/* Compile by executing: gcc -o getch getch.c */
/* Found at http://developer.apple.com/documentation/OpenSource/Conceptual/ShellScripting/AdvancedTechniques/chapter_9_section_3.html */

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
    int ch;
    int flags = fcntl(STDIN_FILENO, F_GETFL);
    if (flags == -1) return -1; // error
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    ch = fgetc(stdin);
    if (ch == EOF) return -1;
    if (ch == -1) return -1;
    printf("%c", ch);
    return 0;
}
