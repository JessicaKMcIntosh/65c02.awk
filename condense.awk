#!/usr/bin/awk -f
# vim600: set foldmethod=marker: # Faster folding in VIM.
#
# 65c02 Object file condenser. {{{1
#
# Condenses multiple 65c02 object files into one.
#
# Objects files must be in plain text format. Address listed first separated by
# a space or colon from the data. Address and data in hexadecimal. Ideally they
# should be the output from a65c02.awk. The object files are read into memory.
# All addresses are checked to make sure there are no collisions. A new object
# file is written without comments and condensed. The data is output in the
# order loaded with 16 bytes per line.
#
# Copyright (C) 2007 Lorance Stinson All rights reserved.  This script is free
# software.  It may be copied or modified according to the same terms as Perl.
#
# For more information email <LoranceStinson+65c02@gmail.com>.
# Or see http://lorance.freeshell.org/

# Documentation: {{{1
#
# Global Variables:
# convert_str       - Used for converting between bases.
# condense=0        - When true the loaded data is disassembled.
# bytes_read=0      - The number of bytes read.
# addr_array=[]     - Used to sequence addresses. bytes_read -> Address.
# data_array=[]     - The data loaded from the file. Address -> Byte.

# AWK BEGIN/END/line. {{{1

# Initialization. {{{2
BEGIN {
    # Used for converting the base of a number,
    convert_str = "0123456789ABCDEF"

    # Nothing read in yet.
    bytes_read = 0

    # Default to disassembling the data.
    condense = 1
}

# Condense the data if there were no errors.. {{{2
END {
    if (condense == 1) {
        condense_code()
    }
}

# Load object files passed on the command line or via STDIN. {{{2
/^[0-9A-Fa-f]*/ && !/^[ \t]*[#;]/ {
    load_object($0)
}

# Functions. {{{1

# condense_code() - Condenses the loaded code. {{{2
# byte  - Byte counter. (Private)
# addr  - The current address. (Private)
# paddr - The previous address. (Priavte)
# i     - Counter. (Private)
function condense_code(byte, addr, paddr, i) {
    # Set the previous address to the first address - 1.
    paddr = addr_array[0] - 1

    # Start the loop to print the data.
    byte = 0
    while (byte < bytes_read) {
        # Print the address for the line.
        printf "%04s", convert_base(10, 16, addr_array[byte])

        # Print 16 bytes per line.
        for (i = 1; i <= 16; i++) {
            # Get the address for the byte.
            addr = addr_array[byte]

            # Make sure the address did not change unexpectedly.
            if (addr != (paddr + 1)) {
                paddr = addr - 1
                break
            }

            # Print the byte for the address.
            printf " %02s", convert_base(10, 16, data_array[addr])
            byte++

            # Make sure we do not go past the end.
            if (byte >= bytes_read) {
                break
            }

            # Save the address for the next round.
            paddr = addr
        }

        # End the line.
        print ""
    }
}

# convert_base(from, to, number) - Convert the base of a number. {{{2
# Works by converting the number to base 10 then to the desired base.
# from      - The base the number is currently in.
# to        - The base to convert the number to.
# number    - The number to convert.
# new       - Temporary number used for conversions. (Private)
# i         - Counter. (Private)
function convert_base(from, to, number, new, i) {
    # If the bases are the same just return the number.
    if (from == to) {
        return number + 0; # Add 0 to make sure it is a number.
    }

    # Convert the number to base 10 if it is not already.
    if (from != 10) {
        # Make sure the number is upper case if might contain letters.
        if (from > 10) {
            number = toupper(number)
        }

        # Perform the actual conversion.
        new = 0
        for(i = 1; i < length(number) + 1; i++){
            new = (new * from) + index(convert_str, substr(number, i, 1)) - 1
        }
        number = new
    }

    # Convert the number from base 10 to the desired base.
    if (to != 10 ) {
        new = ""
        while(number > 0){
            new = substr(convert_str, (number % to) + 1,1 ) new
            number = int(number / to)
        }
        number = new
    }

    # Return the number.
    return number
}

# load_object(text) - Loads object files. {{{2
# text  - The text to load.
# addr  - The current address. (Private)
# i     - Counter. (Private)
# data  - The data to load. (Private)
# num   - The number of items in data. (Private)
function load_object(text, line, addr, i, data, num) {
    # Strip comments.
    sub(/ *[#;].*$/, "", text)

    # Return if there is no text to process.
    if (length(text) == 0) {
        return
    }

    # Split the line using space, tab and : characters.
    num = split(text, data, /[ :\t]/)

    # Get the starting address.
    addr = convert_base(16, 10, data[1])

    # Store the data into the data stack.
    for (i = 2; i <= num; i++) {
        # Check for invalid characters.
        if (match(data[i], /[^0-9A-Fa-f]/) != 0) {
            printf "Invalid character '%s' on line # %d of %s.\n", \
                   substr(data[i], RSTART, 1), \
                   FNR, \
                   (FILENAME ? sprintf("of file '%s'", FILENAME) : "STDIN")
            condense = 0
            exit 1
        }

        # Store the data.
        while (length(data[i]) > 0) {
            # Make sure the address has not already been used yet.
            if (addr in data_array) {
                printf "Address '%04s' repeated on line # %d of %s.\n", \
                       convert_base(10, 16, addr), \
                       FNR, \
                       (FILENAME ? sprintf("of file '%s'", FILENAME) : "STDIN")
                condense = 0
                exit 1
            }

            # Save the address.
            addr_array[bytes_read] = addr

            # Save the data.
            if (length(data[i]) > 2) {
                # Grab the first two characters.
                data_array[addr] = convert_base(16, 10, substr(data[i], 1, 2))
                data[i] = substr(data[i], 3, length(data[i]) - 2)
            } else {
                # Use the whole string.
                data_array[addr] = convert_base(16, 10, data[i])
                data[i] = ""
            }

            # Advance the address and bytes counter.
            addr++
            bytes_read++

        }
    }
}

