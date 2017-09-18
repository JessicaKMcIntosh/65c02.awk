#!/usr/bin/awk -f
# vim600: set foldmethod=marker: # Faster folding in VIM.
#
# 65c02 Disassembler. {{{1
#
# Disassembles 65c02 object files.
#
# Objects files must be in plain text format. Address listed first separated by
# a space or colon from the data. Address and data in hexadecimal.
#
# An option data file cab be loaded with the -v conf=FILE command line option.
# The file can contain symbols and locations that are data. Data locations are
# not disassembled. The symbols are formatted "SYMBOL = VALUE". The value is
# expected to be in hexadecimal. Data locations are formatted "ADDRESS
# LENGTH". The address is expected to be in hexadecimal. The length is
# optional and is expected to be in decimal. Comments can start with either a
# "#" or ";" character and are ignored.
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
# addr_array=[]     - Address stack. Stored as HEX.
#                     Indexed by the number of bytes read.
# instr_array=[]    - Instruction stack. Sored as decimal.
#                     Indexed by the number of bytes read.
# bytes_read=0      - The number of bytes read.
# disassemble=0     - When true the loaded data is disassembled.
# sym_array=[]      - The symbols used in the source.
#                     sym_array[HEX address] = NAME.
# data_array=[]     - Locations in memory that are data and not code.
# inst_decode=""    - Instruction decoding string. XXXYZ
#                     XXX = Instruction name.
#                     Y   = Addressing mode. Used by print_operand().
#                     Z   = Number of operand bytes.

# AWK BEGIN/END/line. {{{1

# Initialization. {{{2
BEGIN {
    # Used for converting the base of a number,
    convert_str = "0123456789ABCDEF"

    # Instruction decoding string.
    inst_decode = "BRKB0ORAM1          TSBZ1ORAZ1ASLZ1     PHPB0ORAI1ASLa0" \
                  "     TSBA2ORAA2ASLA2     BPLZ1ORAN1ORAz1     TRBZ1ORAx1" \
                  "ASLx1     CLCB0ORAY2INAB0     TRBA2ORAX2ASLX2     JSRA2" \
                  "ANDM1          BITZ1ANDZ1ROLZ1     PLPB0ANDI1ROLa0     " \
                  "BITA2ANDA2ROLA2     BMIZ1ANDN1ANDz1     BITx1ANDx1ROLx1" \
                  "     SECB0ANDY2DEAB0     BITX2ANDX2ROLX2     RTIB0EORM1" \
                  "               EORZ1LSRZ1     PHAB0EORI1LSRa0     JMPA2" \
                  "EORA2LSRA2     BVCZ1EORN1EORz1          EORx1LSRx1     " \
                  "CLIB0EORY2PHYB0          EORX2LSRX2     RTSB0ADCM1     " \
                  "     STZZ1ADCZ1RORZ1     PLAB0ADCI1RORa0     JMPi2ADCA2" \
                  "RORA2     BVSZ1ADCN1ADCz1     STZx1ADCx1RORx1     SEIB0" \
                  "ADCY2PLYB0     JMPJ2ADCX2RORX2     BRAZ1STAM1          " \
                  "STYZ1STAZ1STXZ1     DEYB0BITI1TXAB0     STYA2STAA2STXA2" \
                  "     BCCZ1STAN1STAz1     STYx1STAx1STXy1     TYAB0STAY2" \
                  "TXSB0     STZA2STAX2STZX2     LDYI1LDAM1LDXI1     LDYZ1" \
                  "LDAZ1LDXZ1     TAYB0LDAI1TAXB0     LDYA2LDAA2LDXA2     " \
                  "BCSZ1LDAN1LDAz1     LDYx1LDAx1LDXy1     CLVB0LDAY2TSXB0" \
                  "     LDYX2LDAX2LDXY2     CPYI1CMPM1          CPYZ1CMPZ1" \
                  "DECZ1     INYB0CMPI1DEXB0     CPYA2CMPA2DECA2     BNEZ1" \
                  "CMPN1CMPz1          CMPx1DECx1     CLDB0CMPY2PHXB0     " \
                  "     CMPX2DECX2     CPXI1SBCM1          CPXZ1SBCZ1INCZ1" \
                  "     INXB0SBCI1NOPB0     CPXA2SBCA2INCA2     BEQZ1SBCN1" \
                  "SBCz1          SBCx1INCx1     SEDB0SBCY2PLXB0          " \
                  "SBCX2INCX2     "

    # Nothing read in yet.
    bytes_read = 0

    # Default to disassembling the data.
    disassemble = 1

    # If a configuration file was specified load it.
    if (conf != "") {
        load_conf()
    }
}

# Disassemble the data if there were no errors.. {{{2
END {
    if (disassemble == 1) {
        dis_asm()
    }
}

# Load object files passed on the command line or via STDIN. {{{2
/^[0-9A-Fa-f]*/ && !/^[ \t]*[#;]/ {
    load_object($0)
}

# Symbol definitions from a65c02.awk. {{{2
/^[;#]@ / {
    sym_array[toupper($4)] = toupper($2)
}

# Data definitions from a65c02.awk. {{{2
/^[;#]! / {
    data_array[toupper($2)] = $3
}

# dis_asm() - Disassembles the saved data. {{{1
# i     - Position counter. (Private)
# item  - The item being disassembled. (Private)
# addr  - The address for the instruction. (Private)
# code  - The OP code for the current instruction. (Private)
# decode- The decoded instruction. (Private)
# mode  - The addressing mode. (Private)
# len   - The instruction length. (Private)
# data  - The op code data. (Private)
function dis_asm(i, item, addr, code, decode, mode, len, data) {
    i = 0
    while (i < bytes_read) {
        # Get the address and OP code.
        addr = sprintf("%04s", convert_base(10, 16, addr_array[i]))
        code = instr_array[i]

        # Decode the instruction.
        if (addr in data_array) {
            # It's data according to the data file.
            i = i + print_data(i, data_array[addr])
            continue
        } else {
            # Find the information in the decoding string.
            decode = substr(inst_decode, ((code * 5) + 1), 5)
        }

        # Print the address and instruction.
        printf addr
        printf " %02s ", convert_base(10, 16, code)

        # Increment the counter.
        i++

        # Setup the variables for this instruction.
        if (decode == "     ") {
            # It was not found. Assume it's data.
            data = sprintf("%02s", convert_base(10, 16, code))
            code = ".byte"
            mode = ""
            len = 0
        } else {
            # It was found.
            data = ""
            code = substr(decode, 1, 3)
            mode = substr(decode, 4, 1)
            len = substr(decode, 5, 1)
        }

        # Get any extra data the instruction requires.
        if (len == 0) {
            printf "      "
        } else if (len == 1) {
            # Get and print the data.
            data = sprintf("%02s", convert_base(10, 16, instr_array[i++]))
            printf data "    "

            # If it's a branch fix the data.
            if (code ~ /^B[^I].$/) {
                # Fix the relative address.
                if (instr_array[i - 1] >= 128) {
                    data = addr_array[i] +  (instr_array[i - 1] - 256)
                } else {
                    data = addr_array[i] + instr_array[i - 1]
                }
                data = sprintf("%04s", convert_base(10, 16, data))

                # See if it's in the symbol table.
                if (data in sym_array) {
                    data = sym_array[data]
                } else {
                    data = "$" data
                }
            } else {
                # See if it's in the symbol table.
                if ("00" data in sym_array) {
                    data = sym_array["00" data]
                } else {
                    data = "$" data
                }
            }
        } else if (len == 2) {
            # Print the data.
            printf"%02s ", convert_base(10, 16, instr_array[i + 0])
            printf"%02s ", convert_base(10, 16, instr_array[i + 1])

            # Turn the data into a word.
            data = word_make(instr_array[i++], instr_array[i++])
            data = sprintf("%04s", convert_base(10, 16, data))

            # See if it's a symbol.
            if (data in sym_array) {
                data = sym_array[data]
            } else {
                data = "$" data
            }
        }

        # Print the instruction and symbol.
        printf "; "
        if (addr in sym_array) {
            printf "%-15s", sym_array[addr]
        } else {
            printf "               "
        }
        printf "%-5s ", code

        # Print the data in the proper format for the mode.
        print_operand(data, mode)

        # Finish the line.
        print ""
    }
}

# Utilities. {{{1

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

# load_conf() - Load a data location file. {{{2
# line  - The current line. (Private)
# addr  - The address. (Private)
# sym   - The symbol. (Private)
# value - The value. (Private)
function load_conf(line, addr, sym, value) {
    while (getline line < conf) {
        # Strip comments and leading white space..
        sub(/[ \t]*[;#].*$/, "", line)
        sub(/^[ \t]*/, "", line)

        # Skip this line if there is nothing left.
        if (length(line) == 0) {
            continue
        }

        # Determine what the line is and load if.
        if (index(line, "=") > 0) {
            # It's a symbol definition.
            # Get the symbol name,
            sym = substr(line, 1, (index(line, " ") - 1))

            # Remove the symbol name and get the value.
            sub(/^[^ \t]*[ \t=]*/, "", line)
            if (match(line, /[0-9A-Fa-f][0-9A-Fa-f]*/) > 0) {
                value = toupper(substr(line, RSTART, RLENGTH))

                # Save the symbol.
                sym_array[sprintf("%04s", value)] = sym
            } else {
                printf "Invalid symbol value '%s' on line '%d'.\n", line, FNR
                disassemble = 0
                exit 1
            }
        } else {
            # It's a data location.
            if (match(line, /[0-9A-Fa-f][0-9A-Fa-f]*/) > 0) {
                # Get the address.
                addr = toupper(substr(line, RSTART, RLENGTH))

                # If there is an optional length grab it.
                sub(/^[^ \t]*[ \t]*/, "", line)
                if (match(line, /[0-9A-Fa-f][0-9A-Fa-f]*/) > 0) {
                    value = toupper(substr(line, RSTART, RLENGTH)) + 0
                } else {
                    value = 1
                }

                # Save the location.
                data_array[sprintf("%04s", addr)] = value
            } else {
                printf "Invalid data definition '%s' on line '%d'.\n", line, FNR
                disassemble = 0
                exit 1
            }
        }
    }
    close(conf)
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
            disassemble = 0
            exit 1
        }

        # Store the data.
        while (length(data[i]) > 0) {
            addr_array[bytes_read] = addr
            if (length(data[i]) > 2) {
                # Grab the first two characters.
                instr_array[bytes_read] = convert_base(16, 10, substr(data[i], 1, 2))
                data[i] = substr(data[i], 3, length(data[i]) - 2)
            } else {
                # Use the whole string.
                instr_array[bytes_read] = convert_base(16, 10, data[i])
                data[i] = ""
            }

            # Advance the address and bytes counter.
            bytes_read++
            addr++
        }
    }
}

# print_data(loc) - Prints data from the saved data. {{{2}
# Returns the number of items printed.
# loc   - The location in the saved data.
# len   - The length of the data segment.
# addr  - The address. (Private)
# sym   - The symbol for the address, if there is one. (Private)
# value - The value to print.
# i     - Counter. (Private)
function print_data(loc, len, addr, sym, value, i) {
    if (len == 2) {
        # Print the data as a .word.
        # Get the address and word.
        addr = sprintf("%04s", convert_base(10, 16, addr_array[loc + i]))
        value = convert_base(10, 16, word_make(instr_array[loc + i], \
                                               instr_array[loc + i + 1]))

        # Get any symbol for the address.
        if (addr in sym_array) {
            sym = sym_array[addr]
        } else {
            sym = ""
        }

        # Print the byte.
        printf "%s %02s %02s    ;%-10s .word %04s\n", \
               addr, \
               convert_base(10, 16, instr_array[loc + i]), \
               convert_base(10, 16, instr_array[loc + i + 1]), \
               sym, \
               value
    } else {
        # Print the data as .bytes.
        for (i = 0; i < len; i++) {
            # Get the address and byte.
            addr = sprintf("%04s", convert_base(10, 16, addr_array[loc + i]))
            value = convert_base(10, 16, instr_array[loc + i])

            # Get any symbol for the address.
            if (addr in sym_array) {
                sym = sym_array[addr]
            } else {
                sym = ""
            }

            # Print the byte.
            printf "%s %02s       ;%-10s .byte %02s\n", addr, value, sym, value
        }
    }

    # Return the number of items printed.
    return len
}

# print_operand(data, mode) - Prints the data in the proper format. {{{2
function print_operand(data, mode) {
    if (mode == "I") { printf "#%s", data }     else
    if (mode == "A") { printf "%s", data }      else
    if (mode == "Z") { printf "%s", data }      else
    if (mode == "z") { printf "(%s)", data }    else
    if (mode == "B") { printf  data }           else
    if (mode == "i") { printf "(%s)", data }    else
    if (mode == "J") { printf "(%s,X)", data }  else
    if (mode == "X") { printf "%s,X", data }    else
    if (mode == "Y") { printf "%s,Y", data }    else
    if (mode == "x") { printf "%s,X", data }    else
    if (mode == "y") { printf "%s,Y", data }    else
    if (mode == "M") { printf "(%s,X)", data }  else
    if (mode == "N") { printf "(%s),Y", data }  else
    if (mode == "a") { printf "A" }             else
    if (mode == "")  { printf data }
}

# word_make(low, high) - Combines the high and low bytes into a word. {{{2
# low   - The low byte.
# high  - The high byte.
function word_make(low, high) {
    return (high * 256) + low
}

