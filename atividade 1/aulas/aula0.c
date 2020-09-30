int main() {
    char s1[] = "HELLO";
    char* s2 = "WORLD";
    char* s3 = s2;
    char *s4 = malloc(sizeof(s3));
    strcpy(s4, s3);
    printf("%s %s\n", s1, s4);
}