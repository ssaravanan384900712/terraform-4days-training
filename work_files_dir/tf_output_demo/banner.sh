#!/bin/bash

clear

COLS=$(tput cols)
ROWS=$(tput lines)

# Your 3 lines
LINE1="What makes you HAPPY?"
LINE2="A QUOTE that changed life"
LINE3="Advice to YOUNGER SELF"

# Fonts largest to smallest
FONTS=("big" "standard" "small" "mini")

# Find best fitting font
best_font="mini"
for font in "${FONTS[@]}"; do
    fits=true
    for line in "$LINE1" "$LINE2" "$LINE3"; do
        width=$(figlet -f "$font" "$line" | awk '{ print length }' | sort -n | tail -1)
        if [ "$width" -gt "$COLS" ]; then
            fits=false
            break
        fi
    done
    if $fits; then
        best_font="$font"
        break
    fi
done

# Count total height needed
total_lines=0
for line in "$LINE1" "$LINE2" "$LINE3"; do
    h=$(figlet -f "$best_font" "$line" | wc -l)
    total_lines=$((total_lines + h + 1))
done

# Add space for emoji lines
total_lines=$((total_lines + 6))

# Vertical center
start_row=$(( (ROWS - total_lines) / 2 ))
[ $start_row -lt 0 ] && start_row=0

# Fill entire screen background (dark purple)
for i in $(seq 1 $ROWS); do
    printf '\e[45m%-*s\e[0m\n' "$COLS" ""
done

current_row=$start_row

# Function to print a centered plain text line
print_centered() {
    local text="$1"
    local color="$2"
    local len=${#text}
    local pad=$(( (COLS - len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    tput cup $current_row 0
    printf '\e[45m%*s\e[0m' "$pad" ""
    printf "${color}%s\e[0m" "$text"
    printf '\e[45m%-*s\e[0m' "$((COLS - pad - len))" ""
    current_row=$((current_row + 1))
}

# Function to print figlet line centered
print_figlet() {
    local text="$1"
    local color="$2"
    while IFS= read -r figline; do
        local len=${#figline}
        local pad=$(( (COLS - len) / 2 ))
        [ $pad -lt 0 ] && pad=0
        tput cup $current_row 0
        printf '\e[45m%*s\e[0m' "$pad" ""
        printf "${color}%s\e[0m" "$figline"
        printf '\e[45m%-*s\e[0m' "$((COLS - pad - len))" ""
        current_row=$((current_row + 1))
    done < <(figlet -f "$best_font" "$text")
    current_row=$((current_row + 1))
}

# --- LINE 1 ---
print_centered "★  What makes you..." "\e[1;93m"
print_figlet   "HAPPY?" "\e[1;97m"

# --- LINE 2 ---
print_centered "♦  A Quote That..." "\e[1;93m"
print_figlet   "CHANGED LIFE" "\e[1;92m"

# --- LINE 3 ---
print_centered "♣  Advice To Your..." "\e[1;93m"
print_figlet   "YOUNGER SELF" "\e[1;96m"

# Bottom prompt
tput cup $((ROWS - 2)) 0
pad=$(( (COLS - 30) / 2 ))
printf '\e[45m%*s\e[1;97m  Press any key to exit...  \e[45m%-*s\e[0m' "$pad" "" "$pad" ""

tput civis
read -n1 -r -p ""
tput cnorm
clear
