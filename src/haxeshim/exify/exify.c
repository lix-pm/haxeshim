/**
 * Here comes a great illustration of my non-existent C skills. 
 * Seems to build ok with TinyCC.
 * The escaping also seems to be just fine, but who knows ...
 */

#include "stdio.h"
#include "windows.h"

void copyArg(char *dest, const char *src) {
	
	int end = strlen(dest);
	
	dest[end++] = ' ';
	dest[end++] = '"';

	int max = strlen(src);

	for (int i = 0; i < max; i++) {
		
		if (src[i] == '"') {
			dest[end++] = '\\';
		}
		dest[end++] = src[i];
	}

	dest[end++] = '"';
	dest[end++] = 0;
}

int main(int argc, const char *argv[])
{
	char str[0x10000];//65K should be enough, right?

	

	strcat(str, "abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789");

	for (int i = 1; i < argc; ++i) {
		copyArg(str, argv[i]);
	}
	
	return system(str);
}