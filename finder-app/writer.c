#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

int main(int argc, char *argv[])
{
    const char *writefile;
    const char *writestr;
    int fd;
    ssize_t nr;
    size_t len;

    /*
     * Setup syslog.
     * LOG_USER is required by the assignment.
     */
    openlog("writer", LOG_PID, LOG_USER);

    /*
     * argv[0] = program name
     * argv[1] = file path
     * argv[2] = string to write
     *
     * So argc must be 3.
     */
    if (argc != 3) {
        syslog(LOG_ERR, "Invalid number of arguments: expected 2, got %d", argc - 1);
        fprintf(stderr, "Error: expected 2 arguments\n");
        fprintf(stderr, "Usage: %s <writefile> <writestr>\n", argv[0]);
        closelog();
        return 1;
    }

    writefile = argv[1];
    writestr = argv[2];

    /*
     * Required LOG_DEBUG message.
     */
    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    /*
     * Equivalent of:
     *
     * echo "$writestr" > "$writefile"
     *
     * O_WRONLY: write only
     * O_CREAT : create file if it does not exist
     * O_TRUNC : overwrite existing file
     *
     * 0644 means:
     * owner can read/write
     * group can read
     * others can read
     */
    fd = open(writefile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd == -1) {
        syslog(LOG_ERR, "Could not open file %s: %s", writefile, strerror(errno));
        fprintf(stderr, "Error: could not open file %s: %s\n", writefile, strerror(errno));
        closelog();
        return 1;
    }

    len = strlen(writestr);

    nr = write(fd, writestr, len);
    if (nr == -1) {
        ssize_t newline_nr = write(fd, "\n", 1);
    	if (newline_nr == -1) {
            syslog(LOG_ERR, "Could not write newline to file %s: %s", writefile, strerror(errno));
            fprintf(stderr, "Error: could not write newline to file %s: %s\n", writefile, strerror(errno));
            close(fd);
            closelog();
            return 1;
    	}
    }

    /*
     * write() can technically write fewer bytes than requested.
     * For normal files it is rare, but proper C checks it.
     */
    if ((size_t)nr != len) {
        syslog(LOG_ERR,
               "Partial write to file %s: expected %zu bytes, wrote %zd bytes",
               writefile,
               len,
               nr);

        fprintf(stderr,
                "Error: partial write to file %s: expected %zu bytes, wrote %zd bytes\n",
                writefile,
                len,
                nr);

        close(fd);
        closelog();
        return 1;
    }

    if (close(fd) == -1) {
        syslog(LOG_ERR, "Could not close file %s: %s", writefile, strerror(errno));
        fprintf(stderr, "Error: could not close file %s: %s\n", writefile, strerror(errno));
        closelog();
        return 1;
    }

    closelog();
    return 0;
}
