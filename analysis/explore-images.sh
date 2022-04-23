#!/bin/bash

#
# This contains scraps of my shell scripts that I used
# to explore encoding moonbird images.
#

# Broad overview:
#            write_all_colors: generates `images/table/#.txt`
#                               -> contains a list of tiles as RGB codes.
#      write_all_image_tables: generates `images/coded-table/#.table.txt`
#                               -> contains a list of tiles as short color codes.
#  write_all_image_tables_rle: generates `images/coded-table-rle/#.table.rle.txt`
#                               -> contains a list of RLE compressed tiles.
#     write_all_rle_bytes_bin: generates `images/bin/#.bin`
#                               -> contains the binary form of the RLE compressed tile list.
#


TILE_SIZE=24
TILE_ROWS=42
TILE_COUNT=$((TILE_ROWS * TILE_ROWS))

# This assembles the list of imagemagick format requests
# to print the RGB value from the center of each 42x42 tile.
function tile_center_specifiers() {
  for (( i = 0; i < TILE_COUNT; i++ )); do
    x=$(($i % $TILE_ROWS))
    y=$(($i / $TILE_ROWS))
    cx=$((($x * $TILE_SIZE) + ($TILE_SIZE/2)))
    cy=$((($y * $TILE_SIZE) + ($TILE_SIZE/2)))
    echo "%[hex:v.p{$cx,$cy}]"
  done
}

# Prints a list of the RGB color for each tile in the specified token ID's image
function colors() {
  local TOKEN_ID=$1
  convert images/png/$TOKEN_ID.png -format "$(tile_center_specifiers | xargs printf "%s\n")" -write info: null:
}

# Prints a list from 0-N
function positions() {
  local N=$1
  for (( i = 0; i < N; i++ )); do
    echo $i
  done
}

# Directly converts a PNG -> List of tile colors -> SVG
function svg_from_image() {
  local N=$1
  cat <<-EOM
<svg xmlns="http://www.w3.org/2000/svg"
     version="1.1"
     width="1008"
     height="1008"
     viewBox="0 0 1008 1008" >
     <defs>
EOM
  paste <(positions $(colors $N | sort -u | wc -l | xargs)) <(colors $N | sort -u) | while read i color; do
      echo "<rect id=\"t${i}\" width=\"${TILE_SIZE}\" height=\"${TILE_SIZE}\" stroke=\"#${color}\" fill=\"#${color}\"/>"
  done
#  colortable | while read i color; do
#    echo "<rect id=\"t${i}\" width=\"${TILE_SIZE}\" height=\"${TILE_SIZE}\" stroke=\"#${color}\" fill=\"#${color}\"/>"
#  done
  echo "</defs>"
  paste <(positions $TILE_COUNT) <(colors $N) | while read i color; do
    x=$(($TILE_SIZE*($i % $TILE_ROWS)))
    y=$(($TILE_SIZE*($i / $TILE_ROWS)))
    echo "<rect x=\"${x}\" y=\"${y}\" width=\"${TILE_SIZE}\" height=\"${TILE_SIZE}\" stroke=\"#${color}\" fill=\"#${color}\"/>"
  done
  cat <<-EOM
</svg>
EOM
}

# Prints the distribution of colors in the first 1000 (in batches of 100)
function color_dist() {
  n=1000
  p=100 # parallel batch size
  for (( i = 0; i < n / p; i++ )); do
    for (( j = 0; j < p; j++ )); do
      colors $(($i + $j)) | sort -u | wc -l &
    done
    wait
  done
}

# Prints the colors used in the first 100 images.
function full_colors() {
  n=100
  p=20 # parallel batch size
  for (( i = 0; i < n / p; i++ )); do
    for (( j = 0; j < p; j++ )); do
      colors $(($i + $j)) | sort -u &
    done
    wait
  done
}

# Builds and saves the list of tile colors for the specified token ID.
function write_colors() {
  local TOKEN_ID=$1
  colors $TOKEN_ID > images/coded-table/$TOKEN_ID.txt
}

# Builds and saves the list of tile colors for all 10,000 token IDs.
function write_all_colors() {
  for (( i = 0; i < 1000; i++ )); do
    printf "\n$(($i / 10))%%: "
    for (( j = 0; j < 10; j++ )); do
      printf "#$((10*$i + $j)) "
      write_colors $((10*$i + $j)) &
    done
    wait
  done
}

# Uses the global color code `table.txt` to print
# the color->code lookup table for the specified token ID.
function write_image_table() {
  local TOKEN_ID=$1
  awk 'FNR==NR{a[$1]=$2;next}{ print $1, a[$1]}' table.txt images/table/$TOKEN_ID.txt
}

# Builds and saves the color->code lookup table for all 10,000 token IDs.
function write_all_image_tables() {
  for (( i = 0; i < 10000; i++ )); do
    write_image_table $i > images/coded-table/$i.table.txt
  done
}

# Prints the RLE-reduced image lookup table for the specified token ID.
function rle_reduce_image_table() {
  local TOKEN_ID=$1
  uniq -c images/coded-table/$TOKEN_ID.table.txt | while read count color code; do
    echo "${count} ${color} ${code}"
  done
}

# Builds and saves the RLE-reduced image lookup table for all 10,000 token IDs.
function write_all_image_tables_rle() {
  for (( i = 0; i < 10000; i++ )); do
    rle_reduce_image_table $i > images/coded-table-rle/$i.table.rle.txt
  done
}

# Prints in hexadecimal the bytes of the RLE-reduced image tile list
# for the specified token ID.
function rle_bytes_hex() {
  local TOKEN_ID=$1
  cat images/coded-table-rle/$TOKEN_ID.table.rle.txt | while read count color code; do
    # count is always <= 32
    # we subtract 1 so that it fits into 5 bits (and zero is invalid)
    printf "%04x" $(((($count - 1) << 11) | $code))
  done
}

# Prints the hex of all colors found across all 10,000 images.
function all_color_bytes_hex() {
  cat all_color_table.txt | while read code color; do
    printf "${color}"
  done
}

# Builds and saves the binary form of the RLE-reduced image tile list
# for all 10,000 token IDs.
function write_all_rle_bytes_bin() {
  for (( i = 0; i < 10000; i++ )); do
    rle_bytes_hex $i | xxd -r -p > images/bin/$i.bin
  done
}

# Uses the text-form of the RLE-reduced image tile list to generate an SVG.
function svg() {
  local N=$1
  cat <<-EOM
<svg xmlns="http://www.w3.org/2000/svg"
     version="1.1"
     width="1008"
     height="1008"
     viewBox="0 0 1008 1008" >
EOM
  # Treat the first pixel as a probable background color and reduce the rects.
  local bgColor=$(head -n 1 images/coded-table-rle/$N.table.rle.txt | cut -d " " -f 2)
  echo "  <rect width=\"100%\" height=\"100%\" fill=\"#${bgColor}\" stroke=\"#${bgColor}\" />"
  local i=0
  cat images/coded-table-rle/$N.table.rle.txt | while read count color code; do
    if [ "$color" = "$bgColor" ]; then
        i=$(($i + $count))
        continue;
    fi
    for (( j = 0; j < count; j++ )); do
      x=$(($TILE_SIZE*($i % $TILE_ROWS)))
      y=$(($TILE_SIZE*($i / $TILE_ROWS)))
      echo "  <rect x=\"${x}\" y=\"${y}\" width=\"${TILE_SIZE}\" height=\"${TILE_SIZE}\" stroke=\"#${color}\" fill=\"#${color}\"/>"
      i=$(($i + 1))
    done
  done
  cat <<-EOM
</svg>
EOM
}

# Prints the RGB hex corresponding to the 0-1608 color code.
function lookup_color() {
  local code=$1
  awk -vcode="${code}" '$2 == code { print $1 }' table.txt
}

# Uses the binary form of the RLE-reduced image file list to generate an SVG.
function svg_from_bin() {
  local N=$1
  cat <<-EOM
<svg xmlns="http://www.w3.org/2000/svg"
     version="1.1"
     width="1008"
     height="1008"
     viewBox="0 0 1008 1008" >
EOM
  local i=0
  local B=$((16#$(head -c 2 images/bin/$N.bin | xxd -ps)))

  # Treat the first pixel as a probable background color and reduce the rects.
  local bgColor=$(lookup_color $(($B & ((1 << 11) - 1) )))
  echo "  <rect width=\"100%\" height=\"100%\" fill=\"#${bgColor}\" stroke=\"#${bgColor}\" />"
  cat images/bin/$N.bin | xxd -ps |tr -d '\n' | while read -n4 h; do
    B=$((16#$h))
    count=$((($B >> 11) + 1))
    code=$(($B & ((1 << 11) - 1) ))
    color=$(lookup_color $code)
    if [ "$color" = "$bgColor" ]; then
      i=$(($i + $count))
      continue;
    fi

    j=0
    while ((j < count)); do
      x=$(($TILE_SIZE*($i % $TILE_ROWS)))
      y=$(($TILE_SIZE*($i / $TILE_ROWS)))
      i=$(($i + 1))
      j=$(($j + 1))
      width=$TILE_SIZE

      # reduce the # of <rect>s by merging identical tiles horizontally (until end of row)
      while ((j < count && i % 42 != 0)); do
        width=$(($width + $TILE_SIZE))
        i=$(($i + 1))
        j=$(($j + 1))
      done
      echo "  <rect x=\"${x}\" y=\"${y}\" width=\"${width}\" height=\"${TILE_SIZE}\" stroke=\"#${color}\" fill=\"#${color}\"/>"
    done
  done
  cat <<-EOM
</svg>
EOM
}

# Generates all 10,000 SVGs
function write_all_svg() {
  for (( i = 0; i < 10000; i++ )); do
    echo "#$i"
    svg $i > images/svg/$i.svg
  done
}

### The following are just scraps of invocation fragments:

#lookup_color 1562
#svg_from_bin 974 > 974.bin.svg
#svg 974 > 974.svg
#write_all_rle_bytes_bin
#rle_bytes 1
#write_all_svg

# RLE file format
# (thinking through RLE entry sizes)
# just looking at run sizes etc, it could fit into:
# 10 bits - run count (max = 1024)
# 11 bits - color code (max = 2048, actual = 1608)
# -> 21 bits per entry, 12 per 256
# but instead it would be nice to fit it into 256-bit words
# 5 bits - run count (max = 32)
# 11 bits - color code (max = 2048, actual = 1608)
# -> 16 bits per entry, 16 per 256

#rle_reduce_image_table 6158
#write_all_image_tables_rle
#write_all_svg
#write_all_image_tables
#paste <(cat all_colors.txt) <(positions $(cat all_colors.txt |wc -l|xargs)) > table.txt
#paste <(positions $(cat all_colors.txt |wc -l|xargs)) <(cat all_colors.txt) > all_color_table.txt
#sort -u images/{0..9999}.txt > all_colors.txt
#full_colors | sort | uniq -c | sort -r
#svg_from_image 6158 > 6158.svg
#color_dist | sort | uniq -c
#colors 6158
#echo "tile colors count: $(colors 6158 |wc -l)"
#paste <(positions $TILE_COUNT) <(colors 6158)