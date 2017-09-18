#!/usr/bin/awk -f
# vim600: set foldmethod=marker: # Faster folding in VIM.
#
# 65c02 Emulator. {{{1
#
# Emulates a 65c02 processor.
#
# Copyright (C) 2007 Lorance Stinson All rights reserved.  This script is free
# software.  It may be copied or modified according to the same terms as Perl.
#
# For more information email <LoranceStinson+65c02@gmail.com>.
# Or see http://lorance.freeshell.org/

# Documentation: {{{1
#
# Global Variables:
# Emulator:
# ram_array[]       - The RAM array.
# register_a=0      - The A register.
# register_x=0      - The X register.
# register_y=0      - The Y register.
# register_pc=0     - The Program Counter.
# register_sp=0     - The Stack Pointer.
# register_st=[]    - The status register.
# emu_state=""      - The state the emulator is in.
#                     H = Halted.
#                     R = Running.
#                     S = Single step.
#                     s = Single step and / was pressed.
#                     Z = Emulator is not run, file error.
# brk_array=[]      - Breakpoint array.
# brk_points=0      - The number of breakpoints set
# input_cycles=0    - Check for user input after this many instructions.
#
# Internal:
# ascii_str         - Used for converting between numbers and characters.
# convert_str       - Used for converting between bases.
# rand_source       - The command to execute to get a random number.
# input_mode        - The command used to set the normal input mode.

# ADC and SBC. {{{1

# add_with_carry(add) - Adds a byte to Register A with carry. {{{2
# Updates the C, N, Z and V flags.
# add   - The byte to add to Register A.
# byte  - The result of the addition. (Private)
# sbyte - The signed result of the addition.(Private)
# carry - The carry bit. (Private)
function add_with_carry(add, byte, sbyte, carry) {
    # Perform the addition.
    # TODO: Handle decimal mode.
    carry = register_st[0]
    byte = register_a + add + carry

    # See if it is larger than a byte.
    if (byte >= 256) {
        # Set the C flag.
        register_st[0] = 1

        # Reduce it to below a byte.
        byte = byte - 256
    } else {
        # Clear the C flag.
        register_st[0] = 0
    }

    # See if there was a signed overflow.
    sbyte = (register_a >= 128 ? register_a - 256 : register_a) + \
            (add >= 128 ? add - 256 : add) + \
            carry
    if (sbyte >= 128 || sbyte <= -129) {
        # Set the V flag.
        register_st[6] = 1
    } else {
        # Clear the V flag.
        register_st[6] = 0
    }

    # Set the N and Z flags.
    update_nz(byte)

    # Set register A.
    register_a = byte
}

# sub_with_carry(add) - Subtracts a byte to Register A with carry. {{{2
# Updates the C, N, Z and V flags.
# sub   - The byte to subtract from to Register A.
# byte  - The result of the addition. (Private)
# sbyte - The signed result of the addition.(Private)
# carry - The carry bit. (Private)
function sub_with_carry(add, byte, sbyte, carry) {
    # Perform the subtraction.
    # TODO: Handle decimal mode.
    carry = 1 - register_st[0]
    byte = register_a - add - carry

    # See if it is less than a 0.
    if (byte < 0) {
        # Set the C flag.
        register_st[0] = 0

        # Reduce it to below a byte.
        byte = byte + 256
    } else {
        # Clear the C flag.
        register_st[0] = 1
    }

    # See if there was a signed overflow.
    sbyte = (register_a >= 128 ? register_a - 256 : register_a) - \
            (add >= 128 ? add - 256 : add) - \
            carry
    if (sbyte >= 128 || sbyte <= -129) {
        # Set the V flag.
        register_st[6] = 1
    } else {
        # Clear the V flag.
        register_st[6] = 0
    }
    # Set the N and Z flags.
    update_nz(byte)

    # Set register A.
    register_a = byte
}

# Address calculation. {{{1

# addr_index_ind(byte, indx) - Returns the index indirect address for the byte. {{{2
# byte  - The location in the zero page.
# indx  - An optional index.
# addr  - The base address. (Private)
function addr_index_ind(byte, indx, addr) {
    addr = byte_add(byte, indx)
    return word_make(mem_fetch(addr), mem_fetch(byte_add(addr, 1)))
}

# addr_ind_index(byte, indx) - Returns the indirect index address for the byte. {{{2
# byte  - The location in the zero page.
# indx  - An optional index.
function addr_ind_index(byte, indx) {
    return word_add(word_make(mem_fetch(byte), mem_fetch(byte_add(byte, 1))), indx)
}

# addr_rel(rel) - Calculates a relative address. {{{2
# Relative addresses are treated as signed values.
# rel   - The relative address.
function addr_rel(rel) {
    return word_add(register_pc, (rel >= 128 ? rel - 256 : rel))
}

# AWK BEGIN/END/line. {{{1

# Initialization. {{{2
BEGIN {
    # This isn't really used. Just set it to a space.
    FS = " "

    # Used for converting the base of a number,
    convert_str = "0123456789ABCDEF"

    # Used for converting between numbers and characters.
    ascii_str = " !\"#$%&'()*+,-./0123456789:;<=>?@" \
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`" \
                "abcdefghijklmnopqrstuvwxyz{|}~ "

    # The random number source.
    # Other candidates are /dev/random or the fortune program.
    rand_source = "dd if=/dev/urandom bs=1 count=32 2>/dev/null | cksum"

    # The command used to set the normal input mode.
    # Disables echo and canoical mode.
    # Sets the minimum character and time to 0 to
    # read a single character without blocking.
    input_mode = "stty -echo -icanon min 0 time 0"

    # Initialize the registers.
    register_a = 0
    register_x = 0
    register_y = 0
    register_pc = 0
    register_sp = 255
    string_array(register_st, convert_base(10, 2, 32))

    # Start the emulator halted.
    emu_state = (emu_state ? emu_state : "H")

    # Cehck for user input every 100 instructions.
    input_cycles = 100

    # No breakpoints set yet.
    brk_points = 0

    # Initialize the display memory.
    mem_clear(49152, 49392)
}

# Start the virtual machine. {{{2
END {
    if (emu_state != "Z") {
        # Get the starting location from the Reset vector.
        register_pc = word_make(mem_fetch(65532), mem_fetch(65533))

        # Paint the main display.
        system("clear")
        draw_main()
        draw_status()

        # Set the normal input mode.
        system(input_mode)

        # Run the emulator.
        emulate()

        # Update the system status.
        draw_status()

        # Turn echo back on and enable canonical mode.
        system("stty echo icanon")
        put_cursor(24, 0)
    }
}

# Load object files passed on the command line or via STDIN. {{{2
/^[0-9A-Fa-f]*/ {
    load_object($0)

}

# Bit, byte and word manipulation. {{{1

# bit_get(byte, bit) - Returns the specified bit from the byte. {{{2
# byte  - The byte to fetch the bit from.
# bit   - The bit to fetch. Counting from 0.
function bit_get(byte, bit) {
    # Make sure the bit is in bounds.
    if (bit > 7) {
        return 0
    }

    # Return the specified bit.
    return (substr(sprintf("%08s", convert_base(10, 2, byte)), 8 - bit, 1) + 0)

}

# bit_set(byte, bit, value) - Returns the byte with the specified bit set. {{{2
# byte  - The byte to set a bit in.
# bit   - The bit to set. Counting from 0.
# value - The value to set the bit to.
function bit_set(byte, bit, value) {
    # Make sure the bit is in bounds.
    if (bit > 7) {
        return 0
    }

    # Convert the byte to binary.
    byte = sprintf("%08s", convert_base(10, 2, byte))

    # Set the specified bit.
    return convert_base(2, 10,
                (bit < 7 ? substr(byte, 1, 8 - bit - 1) : "") \
                value \
                (bit > 0 ? substr(byte, 8 - bit + 1, bit) : ""))
}

# byte_add(bytea, byteb) - Adds two bytes together. {{{2
# bytea - The first byte.
# byteb - The second byte.
# byte  - The new byte. (Private)
function byte_add(bytea, byteb, byte) {
    # Add the bytes.
    byte = bytea + byteb

    # Return the new byte,
    return (byte >= 256 ? byte - 256 : byte)
}

# byte_and(bytea, byteb) - Performs a bitwise AND of two bytes. {{{2
# bytea - The first byte.
# byteb - The second byte.
# byte  - The new byte. (Private)
# i     - Byte counter. (Private)
function byte_and(bytea, byteb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the AND.
    byte = ""
    for (i = 1; i <= 8; i++) {
        if (substr(bytea, i, 1) == 1 && substr(byteb, i, 1) == 1) {
            byte = byte 1
        } else {
            byte = byte 0
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# byte_div(bytea, byteb) - Divides a byte from another. {{{2
# bytea - The byte to divide from.
# byteb - The byte to divide.
# byte  - The new byte. (Private)
function byte_div(bytea, byteb, byte) {
    # Divide the byte.
    byte = int(bytea / byteb)

    # Return the new byte,
    return byte
}

# byte_high(word) - Returns the high byte from the word. {{{2
# word  - The word to get the high byte from.
function byte_high(word) {
    return int(word / 256)
}

# byte_low(word) - Returns the low byte from the word. {{{2
# word  - The word to get the low byte from.
function byte_low(word) {
    return (word % 256)
}

# byte_mul(bytea, byteb) - Multiplies two bytes together. {{{2
# bytea - The first byte.
# byteb - The second byte.
# byte  - The new byte. (Private)
function byte_mul(bytea, byteb, byte) {
    # Multiply the bytes.
    byte = bytea * byteb

    # Return the new byte,
    return (byte >= 256 ? byte % 256 : byte)
}

# byte_not(bytea, byteb) - Performs a bitwise NOT of a byte. {{{2
# byte  - The byte to not.
function byte_not(byte){
    return 255 - byte
}

# byte_or(bytea, byteb) - Performs a bitwise OR of two bytes. {{{2
# bytea - The first byte.
# byteb - The second byte.
# byte  - The new byte. (Private)
# i     - Byte counter. (Private)
function byte_or(bytea, byteb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the OR.
    byte = ""
    for (i = 1; i <= 8; i++) {
        if (substr(bytea, i, 1) == 1 || substr(byteb, i, 1) == 1) {
            byte = byte 1
        } else {
            byte = byte 0
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# byte_sub(bytea, byteb) - Subtracts a byte from another. {{{2
# bytea - The byte to subtract from.
# byteb - The byte to subtract.
# byte  - The new byte. (Private)
function byte_sub(bytea, byteb, byte) {
    # Subtract the byte.
    byte = bytea - byteb

    # Return the new byte,
    return (byte < 0 ? byte + 256 : byte)
}

# byte_xor(bytea, byteb) - Performs a bitwise XOR of two bytes. {{{2
# bytea - The first byte.
# byteb - The second byte.
# byte  - The new byte. (Private)
# i     - Byte counter. (Private)
function byte_xor(bytea, byteb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the XOR.
    byte = ""
    for (i = 1; i <= 8; i++) {
        if (substr(bytea, i, 1) == substr(byteb, i, 1)) {
            byte = byte 0
        } else {
            byte = byte 1
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# word_make(low, high) - Combines the high and low bytes into a word. {{{2
# low   - The low byte.
# high  - The high byte.
function word_make(low, high) {
    return (high * 256) + low
}


# word_add(worda, wordb) - Adds two words together. {{{2
# worda - The first word.
# wordb - The second word.
# word  - The new word. (Private)
function word_add(worda, wordb, word) {
    # Add the words.
    word = worda + wordb

    # Return the new word,
    return (word >= 65536 ? word - 65536 : word)
}

# word_sub(worda, wordb) - Subtracts a word from another. {{{2
# worda - The word to subtract from.
# wordb - The word to subtract.
# word  - The new word. (Private)
function word_sub(worda, wordb, word) {
    # Subtract the word.
    word = worda - wordb

    # Return the new word,
    return (word < 0 ? word + 65536 : word)
}

# Input/Output {{{1

# draw_brkpts() - Draws the currently set breakpoints. {{{2
# addr  - Temporary address. (Private)
# i     - Temporary counter. (Private)
function draw_brkpts(addr, i) {
    # Print the breakpoints.
    i = 0
    for (addr in brk_array) {
        i++
        put_cursor(7 + i, 34)
        printf "0x%04s", convert_base(10, 16, addr)
    }

    # Clear the empty slots.
    for (i = brk_points + 1; i <= 6; i++) {
        put_cursor(7 + i, 34)
        printf "      "
    }
}

# draw_display() - Draw the emulator text display. {{{2
# i     - Address counter. {Private)
function draw_display(i) {
    for (i = 49152; i <= 49391; i++) {
        # Position the cursor if on a new line.
        if (i == 49152 || \
            i == 49192 || \
            i == 49232 || \
            i == 49272 || \
            i == 49312 || \
            i == 49352) {
            put_cursor((int((i - 49152) / 40) + 1), 1)
        }

        # Print the character.
        printf "%s", num_char(ram_array[i])
    }
}

# draw_main() - Draws the main display. {{{2
function draw_main() {
    print "+----------------------------------------+-------- AWK 65c02 Emulator -------+"
    print "|                                        | ` = Escape the next character.    |"
    print "|                                        | ! = Quit the emulator.            |"
    print "|                                        | @ = Set the value for a register. |"
    print "|                                        | # = Halt/run the emulator.        |"
    print "|                                        | $ = Hexdump.                      |"
    print "|                                        | % = Change memory contents.       |"
    print "+---------------------------+---+--------+ ^ = Pause the emulator.           |"
    print "| Register A:               | H |        | & = Reset the emulator.           |"
    print "| Register X:               | A |        | * = Set a breakpoint. (Up to 6)   |"
    print "| Register Y:               | L |        | _ = Dump the emulators memory.    |"
    print "| Stack Pointer:            | T |        | ? = Update the status display.    |"
    print "| Program Counter:          +---+        | / = SingleStep the emulator.      |"
    print "| Processor Status:         |   |        |   LoranceStinson+65c02@gmail.com  |"
    print "+------ System Status ------+Key+-BrkPts-+-----------------------------------+"
}

# draw_state() - Draw the emulator state. {{{2
function draw_state() {
    if (emu_state == "R") {
        # Running.
        printf "[9;31HR[10;31HU[11;31HN[12;31H "
    } else if (emu_state == "H") {
        # Halted.
        printf "[9;31HH[10;31HA[11;31HL[12;31HT "
    } else if (emu_state == "S" || emu_state == "s") {
        # Single step.
        printf "[9;31HS[10;31HT[11;31HE[12;31HP "
    }
}

# draw_status() - Updates the system state. {{{2
function draw_status() {
    printf "[9;26H%02s\n", convert_base(10, 16, register_a)
    printf "[10;26H%02s\n", convert_base(10, 16, register_x)
    printf "[11;26H%02s\n", convert_base(10, 16, register_y)
    printf "[12;26H%02s\n", convert_base(10, 16, register_sp)
    printf "[13;24H%04s\n", convert_base(10, 16, register_pc)
    printf "[14;21H%s%s%s%s%s%s%s\n", \
           (register_st[7] == 1 ? "N" : "n"), \
           (register_st[6] == 1 ? "V" : "v"), \
           (register_st[4] == 1 ? "B" : "b"), \
           (register_st[3] == 1 ? "D" : "d"), \
           (register_st[2] == 1 ? "I" : "i"), \
           (register_st[1] == 1 ? "Z" : "z"), \
           (register_st[0] == 1 ? "C" : "c")
}

# dump_memory() - Dump the emulators memory. {{{2
function dump_memory (file_name, addr, paddr, bytes) {
    # Get the file name.
    file_name = read_line_prompt("File name (mem_dump.obj): ")
    if (!file_name) {
        file_name = "mem_dump.obj"
    }

    # Dump the emulators memory.
    print "# AWK 65c02 Emulator memory dump." > file_name
    paddr = -2
    bytes = 0
    for (addr = 0; addr <= 65535; addr++) {
        if (addr in ram_array && ram_array[addr] != 0) {
            # If the address changed more than 1 or we have printed more than
            # 16 bytes per line move on to a new line.
            if (paddr != (addr - 1) || bytes >= 16) {
                printf "\n%04s", convert_base(10, 16, addr) >> file_name
                bytes = 0
            }

            # Print the byte at the current address.
            printf " %02s", convert_base(10, 16, ram_array[addr]) >> file_name

            # Increment the byte per line counter and set the previous address.
            bytes++
            paddr = addr
        }
    }

    # LEt the user know we are finished.
    put_cursor(15, 0)
    printf "* Memory dump to '%s' completed.", file_name
}

# handle_normal_char(char) - Handles a normal user input character. {{{2
# If the character is not recognized it is treated as a null.
# char  - The character to convert.
# num   - The ASCII number for the character. (Private)
# pchar - The character to print on the display. (Private)
function handle_normal_char(char, num, pchar) {
    # Try to convert the character.
    if (char == "" || char == "") {
        # Backspace.
        num = 8 ;   pchar = " BS"
    } else if (char == "\015") {
        # Linefeed / Carriage Return
        num = 10;   pchar = " CR"
    } else if (char == "\014") {
        # Linefeed / Carriage Return
        num = 14;   pchar = " FF"
    } else if (char == "\011") {
        # Tab.
        num = 9 ;   pchar = "TAB"
    } else if (char == "\004") {
        # End of line.
        num = 4 ;   pchar = "EOL"
    } else {
        num = index(ascii_str, char)
        if (num > 0) {
            num = num + 31
        }
        if (char == " ") {
            pchar = "SPC"
        } else {
            pchar = " " char " "
        }
    }

    # Print the character on the display.
    printf "[14;30H%s", pchar

    # Store it in 0xC0FF
    ram_array[49406] = num
    ram_array[49407] = num
}

# handle_special_char(char) - Handle input from the user. {{{2
# Returns the character if it is special and handled later.
# char  - The character the user entered.
# addr  - Temporary address. (Private)
function handle_special_char(char, addr) {
    if (char == "@") {          # Set a registers value.
        # Get the register from the user.
        read_reg()
    } else if (char == "_") {   # Dump the emulators memory.
        dump_memory()
    } else if (char == "#") {   # Toggle between Halt and Run.
        if (emu_state == "R") {
            change_state("H")
        } else {
            change_state("R")
        }
    } else if (char == "$") {   # Hexdump.
        # Get the address from the user.
        addr = read_addr()

        # Print a hexdump centered on the address.
        if (addr != "") {
            hex_dump_int(addr)
        }
    } else if (char == "%") {   # Change memory contents.
        # Get the address from the user.
        addr = read_addr()

        # Make sure they entered an address.
        if (addr == "") {
            return ""
        }

        # Read bytes and write them to memory.
        while (1) {
            # Get a byte.
            char = read_line_prompt( \
                   sprintf("Enter a byte in hex, blank to exit. %04s (%02s): ", \
                           convert_base(10, 16, addr),
                           convert_base(10, 16, ram_array[addr])))

            # Return if they did not enter anything.
            if (char == "") {
                return ""
            }

            # Write the byte to memory.
            mem_write(addr, convert_base(16, 10, char))

            # Increment the address.
            addr++
        }
    } else if (char == "^") {   # Pause the emulator.
        if (emu_state == "R") {
            draw_status()
            hex_dump_int(register_pc)
            pause_emu("")
        }
    } else if (char == "&") {   # Reset the emulator.
        # Get the starting location from the Reset vector.
        register_pc = word_make(mem_fetch(65532), mem_fetch(65533))
    } else if (char == "*") {   # Set a breakpoint.
        # Get the address from the user.
        addr = read_addr()

        # Make sure they entered an address.
        if (addr == "") {
            return ""
        }

        if (addr in brk_array) {
            # It's already set, delete it.
            delete brk_array[addr]
            brk_points--
        } else {
            # Make sure not too many are set already.
            if (brk_points >= 6) {
                pause_emu("* Too many breakpoints set already.")
                return ""
            }

            # Add the breakpoint.
            brk_array[addr] = 1
            brk_points++
        }

        # Update the breakpoints.
        draw_brkpts()
    } else if (char == "?") {   # Update the status.
        draw_status()
        hex_dump_int(register_pc)
    } else if (char == "/") {   # Single step.
        change_state("s")
    } else {                    # Normal or special and not handled here.
        return char
    }

    # Return to emulation.
    return ""
}

# hex_dump(low, high, target) - Dump RAM as a hex table. {{{2
# Prints a 16 byte wide table.
# low   - The byte to start dumping from.
# high  - The byte to stop dumping at.
# target- The target address.
# i     - Byte counter. (Private)
function hex_dump(low, high, target, i) {
    # Print the initial address.
    printf "%04s :", convert_base(10, 16, low)

    # Fill in blanks so everything lines up.
    if ((low % 16) != 0) {
        for (i = 0; i < (low % 16); i++) {
            printf "   "
        }
    }
    
    # Make sure we don't go past the end of memory.
    if (high > 65535) {
        high = 65535
    }

    # Print the hexdump.
    for (i = low; i <= high; i++) {
        # Print the address if at a new line.
        if ((i != low) && ((i % 16) == 0)) {
            printf "\n%04s :", convert_base(10, 16, i)
        }

        # Print a marker next to the target.
        if (i == target) {
            printf ">"
        } else {
            printf " "
        }

        # Print the memory value.
        printf "%02s", convert_base(10, 16, ram_array[i])
    }
}

# hex_dump_int(addr) - Interactive hex dump. {{{2
# Performs a hexdump intended for interactive use.
# Prints three lines centered around the target.
# addr  - The address to dump.
# start - The starting address. (Private)
function hex_dump_int(addr, start) {
    # Start the dump on a boundary.
    start = addr
    if (start < 16) {
        start = 16
    }

    # Make sure the dump does not go past the end of memory.
    if ((start + 16) > 65535) {
        start = start - 16
    }

    # Perform the dump.
    put_cursor(16, 0)
    print "Active Memory:"
    hex_dump(start - (start % 16) - 16, \
             start - (start % 16) + 31, \
             addr)

    # Dump the stack.
    print ""
    print "Active Stack:"
    addr = word_make(register_sp, 1)
    start = addr
    while ((start - (start % 16) + 47) > 511) {
        start = start - 16
    }
    hex_dump(start - (start % 16), \
             start - (start % 16) + 47, \
             addr)
}

# pause_emu() - Pauses the emulator and qaits for a key press. {{{2
# Returns the character the user pressed.
# msg   - An optional message to give the user.
# char  - The character the user pressed. (Private)
function pause_emu(mesg, char) {
    # Print the message.
    put_cursor(15, 0)
    printf "%-40s * Press any key to resume emulation.", mesg

    # Wait for a key press.
    char = read_char(1)

    # Erase that whole line. There might be a message there.
    put_cursor(15, 0)
    printf "%78s", " "

    # Return the character the user pressed.
    return char
}

# put_cursor(row, col) - Puts the cursor at the row and column. {{{2
# row   - The row to place the cursor.
# col   - The column to place the cursor.
function put_cursor(row, col) {
    printf "[%d;%dH", (row + 1), (col + 1)
}

# read_addr() - Reads an address from the user. {{{2
# Returns the address base 10 or "" if they did not enter anything.
# addr  - The address read from the user.
function read_addr(addr) {
    # Get an address from the user.
    addr = read_line_prompt("Enter the address: ")

    # Make sure they entered an address.
    if (addr == "") {
        # They did not enter anything.
        return ""
    }

    # Return the converted address.
    return convert_base(16, 10, addr)
}

# read_char() - Reads a character from the terminal and returns it. {{{2
# Since Newline is special it are converted to Carriage return.
# block - Determines if blocking IO is used. (1/0)
# char  - The character read. (Private)
function read_char(block, char) {
    # Read from the user.
    char = ""
# XXX This is the old method. Using dd is faster...
#    if (block) {
#        "dd if=/dev/tty bs=1 count=1 2>/dev/null | tr '\n' '\r'" | getline char
#        close("dd if=/dev/tty bs=1 count=1 2>/dev/null | tr '\n' '\r'")
#    } else {
#        "getch | tr '\n' '\r'" | getline char
#        close("getch | tr '\n' '\r'")
#    }
    if (block) {
        system("stty min 1")
    }
    "dd if=/dev/tty bs=1 count=1 2>/dev/null | tr '\n' '\r'" | getline char
    close("dd if=/dev/tty bs=1 count=1 2>/dev/null | tr '\n' '\r'")
    if (block) {
        system("stty min 0")
    }

    # Return the character.
    return char
}

# read_line() - Reads a line from the terminal and returns it. {{{2
# line  - The line read. (Private)
function read_line(line) {
    # Read from the user.
    line = ""
    system("stty echo icanon")
    getline line < "/dev/tty"
    close("/dev/tty")
    system(input_mode)

    # Return the line.
    return line
}

# read_line_prompt() - Reads a line with a prompt. {{{2
# prompt- The prompt to present the user.
# line  - The line read. (Private)
function read_line_prompt(prompt, line) {
    # Display the prompt.
    put_cursor(15, 0)
    printf "%s", prompt

    # Read from the user.
    line = read_line()

    # Clear the line.
    put_cursor(15, 0)
    printf "%75s", " "

    # Return the line.
    return line
}

# read_reg() - Reads a register name and value from the user. {{{2
# Sets the register to the give value.
# reg  - The register read from the user. (Private)
# byte - The byte read from the user. (Private)
function read_reg(reg, byte) {
    # Get a the register from the user.
    reg = toupper(read_line_prompt("Enter the register (A, X, Y, SP, PC, ST): "))

    # Make sure they entered a register.
    if (reg == "") {
        # They did not enter anything.
        return
    }

    # Make sure the register is valid.
    if (!index("SPAXYPCST", reg)) {
        pause_emu("* Invalid register.")
        return ""
    }

    # Make sure they entered a register.
    if (reg == "") {
        return
    }
    
    # PC is handled differnetly.
    if (reg == "PC" || reg == "P") {
        # Get the address from the user.
        byte = read_addr()

        # Set the PC.
        if (byte != "") {
            register_pc = byte
        }

        # Update the display.
        draw_status()
        return
    }


    # Read a byte.
    byte = read_line_prompt( \
           sprintf("Enter a byte in hex, blank to exit. (%s): ", reg))

    # Return if they did not enter anything.
    if (byte == "") {
        return
    }

    # Convert the byte.
    byte = convert_base(16, 10, byte)

    # Set the register.
    if (reg == "A") { register_a = byte } else
    if (reg == "X") { register_x = byte } else
    if (reg == "Y") { register_y = byte } else
    if (reg == "S" || reg == "SP" ) { register_sp = byte } else 
    if (reg == "ST" ) { 
        string_array(register_st, convert_base(10, 2, byte))
    }

    # Update the display.
    draw_status()
}

# Load from memory. {{{1

# load_imm() - Loads an immediate value from memory. {{{2
# The byte that was fetched.
# byte  - The byte fetched from memory. (Private)
function load_imm(byte) {
    # Get the byte.
    byte = mem_fetch(register_pc)

    # Increment the PC.
    register_pc = word_add(register_pc, 1)

    # Return the byte.
    return byte
}

# load_zero(indx) - Loads a value from the zero page. {{{2
# indx  - An optional index.
function load_zero(indx) {
    return mem_fetch(byte_add(load_imm(), indx))
}

# load_zero_ind() - Loads a value from an address stored in zero page. {{{2
# byte  - The zero page location.
function load_zero_ind(byte) {
    byte = load_imm()
    return word_make(mem_fetch(byte), mem_fetch(byte_add(byte, 1)))
}

# load_abs(indx) - Loads a value from an absolute address. {{{2
# indx  - An optional index.
function load_abs(indx) {
    return mem_fetch(word_add(word_make(load_imm(), load_imm()), indx))
}

# Memory fetch/write. {{{1

# mem_clear() - sets a block of memory to 0. {{{2
# start - The starting address.
# end   - The ending address.
function mem_clear(start, end) {
    # Clear the memory.
    for (start; start <= end; start++) {
        ram_array[start] = 0
    }
}

# mem_dec(addr) - Decrements a memory location by one. {{{2
# Updates the N and Z flags.
# addr  - The memory address to decrement.
# byte  - The memory byte. (Private)
function mem_dec(addr, byte){
    # Create the new value.
    byte = byte_sub(mem_fetch(addr), 1)

    # Store the new value.
    mem_write(addr, byte)

    # Update the N and Z flags.
    update_nz(byte)
}

# mem_fetch(addr) - Fetch a value from memory. {{{2
# Handles RAM and IO.
# addr  - The address to fetch from.
# value - The value to return. (Private)
function mem_fetch(addr, value) {
    # Check for special and/or IO.
    if (addr == 49403) {
        # Interface to input_cycles.
        return input_cycles
    }

    # Fetch the value from the RAM array.
    value = ram_array[addr]

    # If they read from the keyboard port clear it.
    if (addr == 49407 && ram_array[49407] != 0) {
        delete ram_array[addr]
    }

    # Return the value.
    return value
}

# mem_inc(addr) - Increment a memory location by one. {{{2
# Updates the N and Z flags.
# addr  - The memory address to increment.
# byte  - The memory byte. (Private)
function mem_inc(addr, byte){
    # Create the new value.
    byte = byte_add(mem_fetch(addr), 1)

    # Store the new value.
    mem_write(addr, byte)

    # Update the N and Z flags.
    update_nz(byte)
}

# mem_write(addr, value) - Write a value to memory. {{{2
# Handles RAM and IO.
# Only permits writing to ROM addresses when loading files.
# addr  - The address to write to
# value - The value to write.
function mem_write(addr, value) {
    # Check for special and/or IO.
    if (addr >= 49152 && addr <= 49391) { # C000 - C0C7
        # Writing to the display.
        ram_array[addr] = value

        # Draw the character if the display update mode is 0.
        if (ram_array[49392] == 0) {
            addr = addr - 49152
            printf "[%d;%dH%s", (int(addr / 40) + 2), ((addr % 40) + 2), num_char(value)
        }
    } else if (addr == 49392) { # C0F0
        # Controls display updating.
        if (value == 0 || (value == 1 && ram_array[49392] != 0)) {
            draw_display()
        }
        ram_array[addr] = value
    } else if (addr == 49393) { # C0F1
        # Clear the display.
        mem_clear(49152, 49391)
        draw_display()
    } else if (addr == 49394) { # C0F2
        # Move the display up one line.
        for (value = 49152; value < 49352; value++) {
            ram_array[value] = ram_array[value + 40]
        }
        mem_clear(49352, 49391)
        draw_display()
    } else if (addr == 49402) { # C0FA
        # Halts the emulator.
        change_state("H")
    } else if (addr == 49403) { # C0FB
        # Interface to input_cycles.
        input_cycles = value
    } else if (addr == 49404 || addr == 49405) { # C0FC C0FD
        # Resets the random number.
        value = random_number(65535)
        ram_array[49404] = byte_low(value)
        ram_array[49405] = byte_high(value)
    } else {
        # Handle the write.
        if (value == 0) {
            # Delete the memory location if the value is zero.
            delete ram_array[addr]
        } else {
            # Write the value to RAM.
            ram_array[addr] = value
        }
    }
}

# Operands. {{{1
# Longer Operands that don't fit anywhere else.

# op_bit(bytea, byteb, setv) - Test two bytes. {{{2
# Updates the N, V and Z flags.
# bytea - The first byte.
# byteb - The second byte.
# setvn - Set the V and N flags. (1/0)
function op_bit(bytea, byteb, setvn) {
# byte  - The new byte. (Private)
    if (setvn == 1) {
        register_st[6] = bit_get(byteb, 6)
        register_st[7] = (byteb >= 128)
    }
    register_st[1] = (byte_and(bytea, byteb) == 0)
}

# op_branch(bit, value, rel) - Performs a branch. {{{2
# Branches if the bit in register_st equals the value.
# bit   - The bit to test.
# value - The value to test against.
# rel   - The relative ammount to branch.
function op_branch(bit, value, rel) {
    if (register_st[bit] == value) {
        register_pc = addr_rel(rel)
    }
}

# op_brk() - Performs a BRK. {{{2
function op_brk() {
    register_pc = word_add(register_pc, 1)
    stack_push(byte_high(register_pc))
    stack_push(byte_low(register_pc))
    stack_push(convert_base(2, 10, array_string(register_st)))
    register_st[4] = 1
    register_st[2] = 1
    register_pc = word_make(mem_fetch(65534), mem_fetch(65535))
}

# op_cmp(bytea, byteb) - Compares two bytes and updates appropriate flags. {{{2
# bytea - The left byte of the comparison.
# byteb - The right byte of the comparison.
# n, c, z - The bits to set. (Private)
function op_cmp(bytea, byteb, n, z, c) {
    # Perform the comparison.
    if (bytea <  byteb) { n = 1; z = 0; c = 0; } else
    if (bytea == byteb) { n = 0; z = 1; c = 1; } else 
    if (bytea >  byteb) { n = 0; z = 0; c = 1; }

    # Set the flags to the proper value.
    register_st[7] = n
    register_st[1] = z
    register_st[0] = c
}

# Shift/Rotate. {{{1

# rotate_left(byte) - Rotates the byte left and returns the new byte. {{{2
# Updates the C, N and Z flags.
# byte  - The byte to rotate.
# bit   - The bit shifted out. (Private)
function rotate_left(byte, bit) {
    # Save the high bit.
    bit = bit_get(byte, 7)

    # Rotate the bits left.
    byte = byte_mul(byte, 2)

    # Set the low bit to the value of the C flag.
    byte = bit_set(byte, 0, register_st[0])

    # Store the saved high bit in the C flag.
    register_st[0] = bit

    # Update the N and Z flags.
    update_nz(byte)

    # Return the new byte.
    return byte
}

# rotate_right(byte) - Rotates the byte right and returns the new byte. {{{2
# Updates the C, N and Z flags.
# byte  - The byte to rotate.
# bit   - The bit shifted out. (Private)
function rotate_right(byte,bit) {
    # Save the low bit.
    bit = bit_get(byte, 0)

    # Shift the bits right.
    byte = byte_div(byte, 2)

    # Set the high bit to the value of the C flag.
    byte = bit_set(byte, 7, register_st[0])

    # Store the saved low bit in the C flag.
    register_st[0] = bit

    # Update the N and Z flags.
    update_nz(byte)

    # Return the new byte.
    return byte
}

# shift_left(byte) - Shifts the byte left and returns the new byte. {{{2
# Updates the C, N and Z flags
# byte  - The byte to shift.
function shift_left(byte) {
    # Save the high bit to the C flag.
    register_st[0] = bit_get(byte, 7)

    # Shift the bits to the left.
    byte = byte_mul(byte, 2)

    # Update the N and Z flags.
    update_nz(byte)

    # Return the new byte.
    return byte
}

# shift_right(byte) - Shifts the byte right and returns the new byte. {{{2
# Updates the C, N and Z flags.
# byte  - The byte to shift.
function shift_right(byte) {
    # Save the low bit in the C flag.
    register_st[0] = bit_get(byte, 0)

    # Shift the bits to the right.
    byte = byte_div(byte, 2)

    # Update the N and Z flags.
    update_nz(byte)

    # Return the new byte.
    return byte
}

# Stack pull/push. {{{1

# stack_pull() - Pulls a byte from the stack and returns it. {{{2
function stack_pull() {
    # Increment the stack pointer.
    register_sp = byte_add(register_sp, 1)

    # Return the byte from the stack.
    return mem_fetch(word_make(register_sp, 1))
}

# stack_push(byte) - Pushes a byte onto the stack. {{{2
# byte  - The byte to push.
function stack_push(byte) {
    # Writ the byte to the stack.
    mem_write(word_make(register_sp, 1), byte)

    # Decrement thestack pointer.
    register_sp = byte_sub(register_sp, 1)
}

# Utilities. {{{1

# array_string(array) - Converts an array to a string. {{{2
# Intended to convert register_st to a binary string.
# array - The array to convert.
# string - The string to return. (Private)
# i     - Position counter. (Private)
function array_string(array, string, i) {
    string = ""
    for (i = 0; i <= 7; i++) {
        string = array[i] string
    }
    return string
}

# change_state(state) - Changes the emulator state. {{{2
function change_state(state) {
    emu_state = state
    draw_state()
    draw_status()
    hex_dump_int(register_pc)
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

# load_object(text) - Loads object data into RAM. {{{2
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

    # Store the data into memory.
    for (i = 2; i <= num; i++) {
        # Check for invalid characters.
        if (match(data[i], /[^0-9A-Fa-f]/) != 0) {
            printf "Invalid character '%s' on line # %d of %s.\n", \
                   substr(data[i], RSTART, 1), \
                   FNR, \
                   (FILENAME ? sprintf("of file '%s'", FILENAME) : "STDIN")
            emu_state = "Z"
            exit 1
        }

        # Load the data.
        while (length(data[i]) > 0) {
            if (length(data[i]) > 2) {
                # Grab the first two characters.
                mem_write(addr, convert_base(16, 10, substr(data[i], 1, 2)))
                data[i] = substr(data[i], 3, length(data[i]) - 2)
            } else {
                # Use the whole string.
                mem_write(addr, convert_base(16, 10, data[i]))
                data[i] = ""
            }

            # Advance the address counter.
            addr++
        }
    }
}

# num_char(number) - Converts a number to a character. {{{2
# num   - The number to convert.
# char  - The character. (Private)
function num_char(num, char) {
    if (num >= 32 && num <= 126) {
        char = substr(ascii_str, num - 31, 1)
    } else {
        char = " "
    }
    return char
}

# random_number(max) - Returns a random number between 1 and max. {{{2
# max   - The maximum number to return.
# num   - The random number. (Private)
function random_number(max, num) {
    rand_source | getline num
    close(rand_source)
    num = ((num + 0) % max) + 1
    return num
}

# string_array(array, string) - Converts an string to a array. {{{2
# Intended to convert a binary string to register_st.
# array - The array to modify.
# string - The string to convert.
# i     - Position counter. (Private)
function string_array(array, string, i) {
    string = sprintf("%08s", string)
    for (i = 0; i <= 7; i++) {
        array[i] = substr(string, 8 - i, 1)
    }
}


# update_nz(byte) - Update the N and Z flags. {{{2
# byte  - The byte to check.
function update_nz(byte) {
    # Negative
    register_st[7] = (byte >= 128)

    # Zero
    register_st[1] = (byte == 0)
}

# The main emulation functions. {{{1

# emulate() - The main emulation loop. {{{2
# count - Counter for reading characters.
# char  - Character read from the user.
# echar - Escape the next character.
# brkpt - A breakpoint was hit.
function emulate(count, char, echar) {
    # Initialize the variables.
    count = 0
    char = ""
    echar = 0
    brkpt = 0

    # Start the main loop.
    while (1) {
        # Check for user input.
        count++
        if (count == input_cycles || emu_state != "R") {
            # Get a character.
            # Block if the emulator is not running.
            char = read_char((emu_state == "R" ? 0 : 1))

            # Process the character.
            if (char) {
                # If this character is not escaped process it.
                if (!echar) {
                    # This handles most input.
                    char = handle_special_char(char)

                    # Check for the remaining special characters.
                    if (char == "!") {
                        # They want to quit.
                        return
                    } else if (char == "`") {
                        # Escape the next character.
                        echar = 1
                        char = ""
                    }
                }

                # If there is still a character it is normal input.
                if (char) {
                    handle_normal_char(char)
                    char = ""
                    echar = 0
                }
            }

            # See if it's time for an interrupt.
            if (count == input_cycles) {
                # TODO: Iterrupt here.
                count = 0
            } else {
                ++count
            }

            # Skip evrything else if halted or single steping and they did not
            # enter a /. Entering / sets emu_state to "s".
            if (emu_state == "H" || emu_state == "S") {
                continue
            }
        }

        # Check for a breakpoint.
        if (brk_points > 0) {
            # If a breakpoint was hit last round then clear the message.
            if (brkpt == 1) {
                put_cursor(15, 0)
                printf "%34s", " "
                brkpt = 0
            }

            # See if the current address is a breakpoint.
            if (register_pc in brk_array) {
                # Update the display.
                draw_status()
                hex_dump_int(register_pc)

                # Tell the user we hit a breakpoint.
                put_cursor(15, 1)
                printf "* Breakpoint encountered at %04s.", \
                       convert_base(10, 16, register_pc)
                brkpt = 1

                # If the emulator is not running halt it.
                if (emu_state == "R") {
                    emu_state = "H"
                    draw_state()
                    continue
                }
            }
        }

        # Process the next instruction.
        process_instr()

        # Update the status and print a hex dump if single steping.
        if (emu_state == "s") {
            draw_status()
            hex_dump_int(register_pc)
            emu_state = "S"
        }
    }
}

# process_instr() - Process the next instruction. {{{2
# op    - The current instruction. (Private)
# addr  - Temporary address. (Private)
function process_instr(op, addr) {
    # Fetch the next instruction.
    op = load_imm()

    # Perform the instruction.
           if (op ==   0) { # 00    BRK
        op_brk()
    } else if (op ==   1) { # 01    ORA (aa,X)
        addr = addr_index_ind(load_imm(), register_x)
        register_a = byte_or(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==   5) { # 05    ORA aa
        register_a = byte_or(register_a, mem_fetch(load_imm()))
        update_nz(register_a)
    } else if (op ==   6) { # 06    ASL aa
        addr = load_imm()
        mem_write(addr, shift_left(mem_fetch(addr)))
    } else if (op ==   8) { # 08    PHP
        stack_push(convert_base(2, 10, array_string(register_st)))
    } else if (op ==   9) { # 09    ORA #aa
        register_a = byte_or(register_a, load_imm())
        update_nz(register_a)
    } else if (op ==  10) { # 0A    ASL A
        register_a = shift_left(register_a)
    } else if (op ==  13) { # 0D    ORA aaaa
        register_a = byte_or(register_a, mem_fetch(word_make(load_imm(), load_imm())))
        update_nz(register_a)
    } else if (op ==  14) { # 0E    ASL aaaa
        addr = word_make(load_imm(), load_imm())
        mem_write(addr, shift_left(mem_fetch(addr)))
    } else if (op ==  16) { # 10    BPL aa      N = 0
        op_branch(7, 0, load_imm())
    } else if (op ==  17) { # 11    ORA (aa),Y
        addr = addr_ind_index(load_imm(), register_y)
        register_a = byte_or(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==  18) { # 12    ORA (aa)
        register_a = byte_or(register_a, load_zero_ind())
        update_nz(register_a)
    } else if (op ==  21) { # 15    ORA aa,X
        register_a = byte_or(register_a, load_zero(register_x))
        update_nz(register_a)
    } else if (op ==  22) { # 16    ASL aa,X
        addr = byte_add(load_imm(), register_x)
        mem_write(addr, shift_left(mem_fetch(addr)))
    } else if (op ==  25) { # 19    ORA aaaa,Y
        register_a = byte_or(register_a, load_abs(register_y))
        update_nz(register_a)
    } else if (op ==  24) { # 18    CLC
        register_st[0] = 0
    } else if (op ==  26) { # 1A    INA
        register_a = byte_add(register_a, 1)
        update_nz(register_a)
    } else if (op ==  29) { # 1D    ORA aaaa,X
        register_a = byte_or(register_a, load_abs(register_x))
        update_nz(register_a)
    } else if (op ==  30) { # 1E    ASL aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_write(addr, shift_left(mem_fetch(addr)))
    } else if (op ==  32) { # 20    JSR aaaa
        addr = word_make(load_imm(), mem_fetch(register_pc))
        stack_push(byte_high(register_pc))
        stack_push(byte_low(register_pc))
        register_pc = addr
    } else if (op ==  36) { # 24    BIT aa
        op_bit(register_a, mem_fetch(load_imm()), 1)
    } else if (op ==  37) { # 25    AND aa
        register_a = byte_and(register_a, mem_fetch(load_imm()))
        update_nz(register_a)
    } else if (op ==  38) { # 26    ROL aa
        addr = load_imm()
        mem_write(addr, rotate_left(mem_fetch(addr)))
    } else if (op ==  33) { # 21    AND (aa,X)
        addr = addr_index_ind(load_imm(), register_x)
        register_a = byte_and(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==  40) { # 28    PLP
        string_array(register_st, convert_base(10, 2, stack_pull()))
    } else if (op ==  41) { # 29    AND #aa
        register_a = byte_and(register_a, load_imm())
        update_nz(register_a)
    } else if (op ==  42) { # 2A    ROL A
        register_a = rotate_left(register_a)
    } else if (op ==  44) { # 2C    BIT aaaa
        op_bit(register_a, mem_fetch(word_make(load_imm(), load_imm())), 1)
    } else if (op ==  45) { # 2D    AND aaaa
        register_a = byte_and(register_a, mem_fetch(word_make(load_imm(), load_imm())))
        update_nz(register_a)
    } else if (op ==  46) { # 2E    ROL aaaa
        addr = word_make(load_imm(), load_imm())
        mem_write(addr, rotate_left(mem_fetch(addr)))
    } else if (op ==  48) { # 30    BMI aa      N = 1
        op_branch(7, 1, load_imm())
    } else if (op ==  49) { # 31    AND (aa),Y
        addr = addr_ind_index(load_imm(), register_y)
        register_a = byte_and(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==  50) { # 32    AND (aa)
        register_a = byte_and(register_a, load_zero_ind())
        update_nz(register_a)
    } else if (op ==  52) { # 34    BIT aa,X
        op_bit(register_a, load_zero(register_x), 1)
    } else if (op ==  53) { # 35    AND aa,X
        register_a = byte_and(register_a, load_zero(register_x))
        update_nz(register_a)
    } else if (op ==  54) { # 36    ROL aa,X
        addr = byte_add(load_imm(), register_x)
        mem_write(addr, rotate_left(mem_fetch(addr)))
    } else if (op ==  56) { # 38    SEC
        register_st[0] = 1
    } else if (op ==  57) { # 39    AND aaaa,Y
        register_a = byte_and(register_a, load_abs(register_y))
        update_nz(register_a)
    } else if (op ==  58) { # 3A    DEA
        register_y = byte_sub(register_y, 1)
        update_nz(register_y)
    } else if (op ==  60) { # 3C    BIT aaaa,X
        op_bit(register_a, load_abs(register_x), 1)
    } else if (op ==  61) { # 3D    AND aaaa,X
        register_a = byte_and(register_a, load_abs(register_x))
        update_nz(register_a)
    } else if (op ==  62) { # 3E    ROL aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_write(addr, rotate_left(mem_fetch(addr)))
    } else if (op ==  64) { # 40    RTI
        string_array(register_st, convert_base(10, 2, stack_pull()))
        register_pc = word_make(stack_pull(), stack_pull())
    } else if (op ==  65) { # 41    EOR (aa,X)
        addr = addr_index_ind(load_imm(), register_x)
        register_a = byte_xor(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==  69) { # 45    EOR aa
        register_a = byte_xor(register_a, mem_fetch(load_imm()))
        update_nz(register_a)
    } else if (op ==  70) { # 46    LSR aa
        addr = load_imm()
        mem_write(addr, shift_right(mem_fetch(addr)))
    } else if (op ==  72) { # 48    PHA
        stack_push(register_a)
    } else if (op ==  73) { # 49    EOR #aa
        register_a = byte_xor(register_a, load_imm())
        update_nz(register_a)
    } else if (op ==  74) { # 4A    LSR A
        register_a = shift_right(register_a)
    } else if (op ==  76) { # 4C    JMP aaaa
        register_pc = word_make(load_imm(), load_imm())
    } else if (op ==  77) { # 4D    EOR aaaa
        register_a = byte_xor(register_a, mem_fetch(word_make(load_imm(), load_imm())))
        update_nz(register_a)
    } else if (op ==  78) { # 4E    LSR aaaa
        addr = word_make(load_imm(), load_imm())
        mem_write(addr, shift_right(mem_fetch(addr)))
    } else if (op ==  80) { # 50    BVC aa      V = 0
        op_branch(6, 0, load_imm())
    } else if (op ==  81) { # 51    EOR (aa),Y
        addr = addr_ind_index(load_imm(), register_y)
        register_a = byte_xor(register_a, mem_fetch(addr))
        update_nz(register_a)
    } else if (op ==  82) { # 52    EOR (aa)
        register_a = byte_xor(register_a, load_zero_ind())
        update_nz(register_a)
    } else if (op ==  85) { # 55    EOR aa,X
        register_a = byte_xor(register_a, load_zero(register_x))
        update_nz(register_a)
    } else if (op ==  86) { # 56    LSR aa,X
        addr = byte_add(load_imm(), register_x)
        mem_write(addr, shift_right(mem_fetch(addr)))
    } else if (op ==  88) { # 58    CLI
        register_st[2] = 0
    } else if (op ==  89) { # 59    EOR aaaa,Y
        register_a = byte_xor(register_a, load_abs(register_y))
        update_nz(register_a)
    } else if (op ==  90) { # 5A    PHY
        stack_push(register_y)
    } else if (op ==  93) { # 5D    EOR aaaa,X
        register_a = byte_xor(register_a, load_abs(register_x))
        update_nz(register_a)
    } else if (op ==  94) { # 5E    LSR aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_write(addr, shift_right(mem_fetch(addr)))
    } else if (op ==  96) { # 60    RTS
        register_pc = word_add(word_make(stack_pull(), stack_pull()), 1)
    } else if (op ==  97) { # 61    ADC (aa,X)
        add_with_carry(mem_fetch(addr_index_ind(load_imm(), register_x)))
    } else if (op == 100) { # 64    STZ aa
        mem_write(load_imm(), 0)
    } else if (op == 101) { # 65    ADC aa
        add_with_carry(mem_fetch(load_imm()))
    } else if (op == 102) { # 66    ROR aa
        addr = load_imm()
        mem_write(addr, rotate_right(mem_fetch(addr)))
    } else if (op == 104) { # 68    PLA
        register_a = stack_pull()
        update_nz(register_a)
    } else if (op == 105) { # 69    ADC #aa
        add_with_carry(load_imm())
    } else if (op == 106) { # 6A    ROR A
        register_a = rotate_right(register_a)
    } else if (op == 108) { # 6C    JMP (aaaa)
        addr = word_make(load_imm(), load_imm())
        register_pc = word_make(mem_fetch(addr), mem_fetch(word_add(addr, 1)))
    } else if (op == 109) { # 6D    ADC aaaa
        add_with_carry(load_abs())
    } else if (op == 110) { # 6E    ROR aaaa
        addr = word_make(load_imm(), load_imm())
        mem_write(addr, rotate_right(mem_fetch(addr)))
    } else if (op == 112) { # 70    BVS aa      V = 1
        op_branch(6, 1, load_imm())
    } else if (op == 113) { # 71    ADC (aa),Y
        add_with_carry(mem_fetch(addr_ind_index(load_imm(), register_y)))
    } else if (op == 114) { # 72    ADC (aa)
        add_with_carry(load_zero_ind())
    } else if (op == 116) { # 74    STZ aa,X
        mem_write(byte_add(load_imm(), register_x), 0)
    } else if (op == 117) { # 75    ADC aa,X
        add_with_carry(load_zero(register_x))
    } else if (op == 118) { # 76    ROR aa,X
        addr = byte_add(load_imm(), register_x)
        mem_write(addr, rotate_right(mem_fetch(addr)))
    } else if (op == 120) { # 78    SEI
        register_st[2] = 1
    } else if (op == 121) { # 79    ADC aaaa,Y
        add_with_carry(load_abs(register_y))
    } else if (op == 122) { # 7A    PLY
        register_y = stack_pull()
        update_nz(register_y)
    } else if (op == 124) { # 7C    JMP (aaaa,X)
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        register_pc = word_make(mem_fetch(addr), mem_fetch(word_add(addr, 1)))
    } else if (op == 125) { # 7D    ADC aaaa,X
        add_with_carry(load_abs(register_x))
    } else if (op == 126) { # 7E    ROR aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_write(addr, rotate_right(mem_fetch(addr)))
    } else if (op == 128) { # 80    BRA aa
        register_pc = addr_rel(load_imm())
    } else if (op == 129) { # 81    STA (aa,X)
        mem_write(addr_index_ind(load_imm(), register_x), register_a)
    } else if (op == 132) { # 84    STY aa
        mem_write(load_imm(), register_y)
    } else if (op == 133) { # 85    STA aa
        mem_write(load_imm(), register_a)
    } else if (op == 134) { # 86    STX aa
        mem_write(load_imm(), register_x)
    } else if (op == 136) { # 88    DEY
        register_y = byte_sub(register_y, 1)
        update_nz(register_y)
    } else if (op == 137) { # 89    BIT #aa
        op_bit(register_a, load_imm(), 0)
    } else if (op == 138) { # 8A    TXA
        register_a = register_x
        update_nz(register_a)
    } else if (op == 140) { # 8C    STY aaaa
        mem_write(word_make(load_imm(), load_imm()), register_y)
    } else if (op == 141) { # 8D    STA aaaa
        mem_write(word_make(load_imm(), load_imm()), register_a)
    } else if (op == 142) { # 8E    STX aaaa
        mem_write(word_make(load_imm(), load_imm()), register_x)
    } else if (op == 144) { # 90    BCC aa      C = 0
        op_branch(0, 0, load_imm())
    } else if (op == 145) { # 91    STA (aa),Y
        mem_write(addr_ind_index(load_imm(), register_y), register_a)
    } else if (op == 146) { # 92    STA (aa)
        addr = load_imm()
        mem_write(word_make(mem_fetch(addr), mem_fetch(byte_add(addr, 1))), register_a)
    } else if (op == 148) { # 94    STY aa,X
        mem_write(byte_add(load_imm(), register_x), register_y)
    } else if (op == 149) { # 95    STA aa,X
        mem_write(byte_add(load_imm(), register_x), register_a)
    } else if (op == 150) { # 96    STX aa,Y
        mem_write(byte_add(load_imm(), register_y), register_x)
    } else if (op == 152) { # 98    TYA
        register_a = register_y
        update_nz(register_a)
    } else if (op == 153) { # 99    STA aaaa,Y
        mem_write(word_add(word_make(load_imm(), load_imm()), register_y), register_a)
    } else if (op == 154) { # 9A    TXS
        register_sp = register_x
        update_nz(register_sp)
    } else if (op == 156) { # 9C    STZ aaaa
        mem_write(word_make(load_imm(), load_imm()), 0)
    } else if (op == 157) { # 9D    STA aaaa,X
        mem_write(word_add(word_make(load_imm(), load_imm()), register_x), register_a)
    } else if (op == 158) { # 9E    STZ aaaa,X
        mem_write(word_add(word_make(load_imm(), load_imm()), register_x), 0)
    } else if (op == 160) { # A0    LDY #aa
        register_y = load_imm()
        update_nz(register_y)
    } else if (op == 161) { # A1    LDA (aa,X)
        register_a = mem_fetch(addr_index_ind(load_imm(), register_x))
        update_nz(register_a)
    } else if (op == 162) { # A2    LDX #aa
        register_x = load_imm()
        update_nz(register_x)
    } else if (op == 164) { # A4    LDY aa
        register_y = mem_fetch(load_imm())
        update_nz(register_y)
    } else if (op == 165) { # A5    LDA aa
        register_a = mem_fetch(load_imm())
        update_nz(register_a)
    } else if (op == 166) { # A6    LDX aa
        register_x = mem_fetch(load_imm())
        update_nz(register_x)
    } else if (op == 168) { # A8    TAY
        register_y = register_a
        update_nz(register_y)
    } else if (op == 169) { # A9    LDA #aa
        register_a = load_imm()
        update_nz(register_a)
    } else if (op == 170) { # AA    TAX
        register_x = register_a
        update_nz(register_x)
    } else if (op == 172) { # AC    LDY aaaa
        register_y = mem_fetch(word_make(load_imm(), load_imm()))
        update_nz(register_y)
    } else if (op == 173) { # AD    LDA aaaa
        register_a = mem_fetch(word_make(load_imm(), load_imm()))
        update_nz(register_a)
    } else if (op == 174) { # AE    LDX aaaa
        register_x = mem_fetch(word_make(load_imm(), load_imm()))
        update_nz(register_x)
    } else if (op == 176) { # B0    BCS aa      C = 1
        op_branch(0, 1, load_imm())
    } else if (op == 177) { # B1    LDA (aa),Y
        register_a = mem_fetch(addr_ind_index(load_imm(), register_y))
        update_nz(register_a)
    } else if (op == 178) { # B2    LDA (aa)
        register_a = load_zero_ind()
        update_nz(register_a)
    } else if (op == 180) { # B4    LDY aa,X
        register_y = load_zero(register_x)
        update_nz(register_y)
    } else if (op == 181) { # B5    LDA aa,X
        register_a = load_zero(register_x)
        update_nz(register_a)
    } else if (op == 182) { # B6    LDX aa,Y
        register_x = load_zero(register_y)
        update_nz(register_x)
    } else if (op == 184) { # B8    CLV
        register_st[6] = 0
    } else if (op == 185) { # B9    LDA aaaa,Y
        register_a = load_abs(register_y)
        update_nz(register_a)
    } else if (op == 186) { # BA    TSX
        register_x = register_sp
        update_nz(register_x)
    } else if (op == 188) { # BC    LDY aaaa,X
        register_y = load_abs(register_x)
        update_nz(register_y)
    } else if (op == 189) { # BD    LDA aaaa,X
        register_a = load_abs(register_x)
        update_nz(register_a)
    } else if (op == 190) { # BE    LDV aaaa,Y
        register_x = load_abs(register_y)
        update_nz(register_x)
    } else if (op == 192) { # C0    CPY #aa
        op_cmp(register_y, load_imm())
    } else if (op == 193) { # C1    CMP (aa,X)
        addr = addr_index_ind(load_imm(), register_x)
        op_cmp(register_a, mem_fetch(addr))
    } else if (op == 196) { # C4    CPY aa
        op_cmp(register_y, mem_fetch(load_imm()))
    } else if (op == 197) { # C5    CMP aa
        op_cmp(register_a, mem_fetch(load_imm()))
    } else if (op == 198) { # C6    DEC aa
        addr = load_imm()
        mem_dec(addr)
    } else if (op == 200) { # C8    INY
        register_y = byte_add(register_y, 1)
        update_nz(register_y)
    } else if (op == 201) { # C9    CMP #aa
        op_cmp(register_a, load_imm())
    } else if (op == 202) { # CA    DEX
        register_x = byte_sub(register_x, 1)
        update_nz(register_x)
    } else if (op == 204) { # CC    CPY aaaa
        op_cmp(register_y, mem_fetch(word_make(load_imm(), load_imm())))
    } else if (op == 205) { # CD    CMP aaaa
        op_cmp(register_a, mem_fetch(word_make(load_imm(), load_imm())))
    } else if (op == 206) { # CE    DEC aaaa
        addr = word_make(load_imm(), load_imm())
        mem_dec(addr)
    } else if (op == 208) { # D0    BNE aa      Z = 0
        op_branch(1, 0, load_imm())
    } else if (op == 209) { # D1    CMP (aa),Y
        addr = addr_ind_index(load_imm(), register_y)
        op_cmp(register_a, mem_fetch(addr))
    } else if (op == 210) { # D2    CMP (aa)
        op_cmp(register_a, load_zero_ind())
    } else if (op == 213) { # D5    CMP aa,X
        op_cmp(register_a, load_zero(register_x))
    } else if (op == 214) { # D6    DEC aa,X
        addr = byte_add(load_imm(), register_x)
        mem_dec(addr)
    } else if (op == 216) { # D8    CLD
        register_st[3] = 0
    } else if (op == 217) { # D9    CMP aaaa,Y
        op_cmp(register_a, load_abs(register_y))
    } else if (op == 218) { # DA    PHX
        stack_push(register_x)
    } else if (op == 221) { # DD    CMP aaaa,X
        op_cmp(register_a, load_abs(register_x))
    } else if (op == 222) { # DE    DEC aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_dec(addr)
    } else if (op == 224) { # E0    CPX #aa
        op_cmp(register_x, load_imm())
    } else if (op == 225) { # E1    SBC (aa,X)
        sub_with_carry(mem_fetch(addr_index_ind(load_imm(), register_x)))
    } else if (op == 228) { # E4    CPX aa
        op_cmp(register_x, mem_fetch(load_imm()))
    } else if (op == 229) { # E5    SBC aa
        sub_with_carry(mem_fetch(load_imm()))
    } else if (op == 230) { # E6    INC aa
        addr = load_imm()
        mem_inc(addr)
    } else if (op == 232) { # E8    INX
        register_x = byte_add(register_x, 1)
        update_nz(register_x)
    } else if (op == 233) { # E9    SBC #aa
        sub_with_carry(load_imm())
    } else if (op == 234) { # EA    NOP
        # Do nothing.
    } else if (op == 236) { # EC    CPX aaaa
        op_cmp(register_x, mem_fetch(word_make(load_imm(), load_imm())))
    } else if (op == 237) { # ED    SBC aaaa
        sub_with_carry(load_abs())
    } else if (op == 238) { # EE    INC aaaa
        addr = word_make(load_imm(), load_imm())
        mem_inc(addr)
    } else if (op == 240) { # F0    BEQ aa      Z = 1
        op_branch(1, 1, load_imm())
    } else if (op == 241) { # F1    SBC (aa),Y
        sub_with_carry(mem_fetch(addr_ind_index(load_imm(), register_y)))
    } else if (op == 242) { # F2    SBC (aa)
        sub_with_carry(load_zero_ind())
    } else if (op == 245) { # F5    SBC aa,X
        sub_with_carry(load_zero(register_x))
    } else if (op == 246) { # F6    INC aa,X
        addr = byte_add(load_imm(), register_x)
        mem_inc(addr)
    } else if (op == 248) { # F8    SED
        register_st[3] = 1
    } else if (op == 249) { # F9    SBC aaaa,Y
        sub_with_carry(load_abs(register_y))
    } else if (op == 250) { # FA    PLX
        register_x = stack_pull()
        update_nz(register_x)
    } else if (op == 253) { # FD    SBC aaaa,X
        sub_with_carry(load_abs(register_x))
    } else if (op == 254) { # FE    INC aaaa,X
        addr = word_add(word_make(load_imm(), load_imm()), register_x)
        mem_inc(addr)
    } else {
        # Anything else acts like a NOP.
    }
}

