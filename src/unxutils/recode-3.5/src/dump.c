/* Conversion of files between different charsets and surfaces.
   Copyright � 1997, 98, 99 Free Software Foundation, Inc.
   This file is part of the GNU C Library.
   Contributed by Fran�ois Pinard <pinard@iro.umontreal.ca>, 1997.

   The `recode' Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public License
   as published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   The `recode' Library is distributed in the hope that it will be
   useful, but WITHOUT ANY WARRANTY; without even the implied warranty
   of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with the `recode' Library; see the file `COPYING.LIB'.
   If not, write to the Free Software Foundation, Inc., 59 Temple Place -
   Suite 330, Boston, MA 02111-1307, USA.  */

#include "common.h"

/* Constants for the possible bases.  If these are reordered, so should be
   the initialisers for the three tables which follow.  */
enum base
{
  OCTAL,
  DECIMAL,
  HEXADECIMAL
};

/* Printing format to use, depending on both the base and the actual number
   of bytes.  The zero byte case is unused.  */
static const char *format_table[3][5]
  = {{ NULL, "0%03o", "0%06o", "0%08o", "0%011o" },
     { NULL, "%3u", "%5u", "%8u", "%10u" },
     { NULL, "0x%02X", "0x%04X", "0x%06X", "0x%08X" }};

/* Number of active digits to expect, depending on both the base and the
   actual number of bytes.  The zero byte case is unused.  The values do not
   include the `0' octal prefix nor the `0x' for hexadecimal.  */
static unsigned width_table[3][5]
  = {{ 0, 3, 6, 8, 11 },
     { 0, 3, 5, 8, 10 },
     { 0, 2, 4, 6, 8 }};

/* Number of printed values per output line, depending on both the base and
   the actual number of bytes.  The zero byte case is unused.  The three
   byte case is also unused, even if the table offers a value for it.  */
static unsigned per_line_table[3][5]
  = {{ 0, 12, 8, 6, 4 },
     { 0, 15, 10, 7, 5 },
     { 0, 12, 8, 7, 6 }};

static bool
dump (RECODE_CONST_STEP step, RECODE_TASK task,
      enum base base, unsigned size)
{
  unsigned per_line = per_line_table[base][size];
  unsigned column = 0;
  int character = get_byte (task);

  while (character != EOF)
    {
      unsigned value = MASK (8) & character;
      unsigned byte_count;
      char buffer[14];
      const char *cursor;

      for (byte_count = 1; byte_count < size; byte_count++)
	{
	  character = get_byte (task);
	  if (character == EOF)
	    break;
	  value = value << 8 | MASK (8) & character;
	}

      /* Write delimiters.  */

      if (column == per_line)
	{
	  put_byte (',', task);
	  put_byte ('\n', task);
	  column = 1;
	}
      else if (column == 0)
	column = 1;
      else
	{
	  put_byte (',', task);
	  put_byte (' ', task);
	  column++;
	}

      /* Write formatted value.  */

      sprintf (buffer, format_table[base][byte_count], value);
      for (cursor = buffer; *cursor; cursor++)
	put_byte (*cursor, task);

      /* Prepare for next iteration.  */

      if (character != EOF)
	character = get_byte (task);
    }

  put_byte ('\n', task);
  TASK_RETURN (task);
}

static bool
undump (RECODE_CONST_STEP step, RECODE_TASK task,
	enum base expected_base, unsigned expected_size)
{
  unsigned per_line = per_line_table[expected_base][expected_size];
  unsigned column = 0;
  int character = get_byte (task);
  bool last_is_short = false;
  bool comma_on_last = character != EOF;

  while (character != EOF)
    {
      unsigned width = 0;
      unsigned value = 0;
      enum base base;
      unsigned size;

      /* Skip whitespace.  But count it, in case of a decimal number.  */

      while (character == ' ' || character == '\t' || character =='\n')
	{
	  if (character == ' ')
	    width++;
	  else
	    RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);

	  character = get_byte (task);
	}
      if (character == EOF)
	{
	  if (width != 0)
	    RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	  break;
	}

      /* Decide the base for the incoming character, possibly abort the
	 recoding if not the proper base.  */

      if (character == '0')
	{
	  character = get_byte (task);

	  if (character == 'x')
	    {
	      if (width != 0)
		RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	      width = 0;
	      base = HEXADECIMAL;
	      character = get_byte (task);
	    }
	  else if (character >= '0' && character <= '9')
	    {
	      /* If followed by 8 or 9, declare it octal nevertheless.  It
		 is the proper thing to do, a reject might occur below.  */
	      if (width != 0)
		RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	      width = 0;
	      base = OCTAL;
	    }
	  else
	    {
	      /* Otherwise, this is a simple, mere, happy decimal zero.  */
	      width++;
	      base = DECIMAL;
	    }
	}
      else if (character >= '1' && character <= '9')
	base = DECIMAL;
      else
	{
	  /* This might be some other line of a C header.  Merely skip the
	     line.  FIXME: This should probably skip multi-line comments or
	     string constants, so to not get fooled by them.  */

	  RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	  while (character != '\n' && character != EOF)
	    character = get_byte (task);
	  if (character == '\n')
	    character = get_byte (task);

	  continue;
	}

      if (base != expected_base)
	RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);

      /* Decode one value.  */

      switch (base)
	{
	case OCTAL:
	  while (character >= '0' && character <= '7')
	    {
	      value = value << 3 | character - '0';
	      width++;
	      character = get_byte (task);
	    }
	  break;

	case DECIMAL:
	  while (character >= '0' && character <= '9')
	    {
	      value = value * 10 + character - '0';
	      width++;
	      character = get_byte (task);
	    }
	  break;

	case HEXADECIMAL:
	  while (true)
	    if (character >= '0' && character <= '9')
	      {
		value = value << 4 | character - '0';
		width++;
		character = get_byte (task);
	      }
	    else if (character >= 'A' && character <= 'F')
	      {
		value = value << 4 | character - 'A' + 10;
		width++;
		character = get_byte (task);
	      }
	    else if (character >= 'a' && character <= 'f')
	      {
		value = value << 4 | character - 'a' + 10;
		width++;
		character = get_byte (task);
	      }
	    else
	      break;
	  break;
	}

      if (width == 0 || width > width_table[base][expected_size])
	{
	  /* If the observed width is greater than expected, the input is
	     invalid, even if the value is in range.  */

	  RETURN_IF_NOGO (RECODE_INVALID_INPUT, step, task);
	}
      else
	{
	  if (last_is_short)
	    RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	  if (!comma_on_last)
	    RETURN_IF_NOGO (RECODE_INVALID_INPUT, step, task);

	  /* Decide how many bytes to produce.  */

	  last_is_short = width < width_table[base][expected_size];
	  if (last_is_short)
	    {
	      /* If the observed width is smaller than expected, accept the
		 value as representing less than the expected number of
		 bytes.  However, the width has to match very exactly.  */

	      for (size = 1; size < 4; size++)
		if (width_table[base][size] == width)
		  break;
	      if (size == 4)
		{
		  RETURN_IF_NOGO (RECODE_INVALID_INPUT, step, task);
		  continue;
		}
	    }
	  else
	    size = expected_size;

	  /* Produce the output bytes.  */

	  {
	    unsigned shift;

	    for (shift = size * 8; shift != 0; shift -= 8)
	      put_byte (MASK (8) & value >> shift - 8, task);
	  }
	}

      /* Skip separators.  */

      comma_on_last = character == ',';
      if (!comma_on_last)
	if (character == '\n')
	  character = get_byte (task);
	else
	  RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
      else
	{
	  character = get_byte (task);
	  if (character == ' ')
	    {
	      column++;
	      character = get_byte (task);
	    }
	  else if (character == '\n')
	    {
	      if (column + 1!= per_line)
		RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);
	      column = 0;
	      character = get_byte (task);
	    }
	}
    }

  if (comma_on_last)
    RETURN_IF_NOGO (RECODE_NOT_CANONICAL, step, task);

  TASK_RETURN (task);
}

#define TRANSFORM(Name, Service, Base, Size) \
  static bool								\
  Name (RECODE_CONST_STEP step, RECODE_TASK task)	\
  {									\
    return Service (step, task, Base, Size);				\
  }

TRANSFORM (data_oct1, dump, OCTAL, 1)
TRANSFORM (data_dec1, dump, DECIMAL, 1)
TRANSFORM (data_hex1, dump, HEXADECIMAL, 1)
TRANSFORM (data_oct2, dump, OCTAL, 2)
TRANSFORM (data_dec2, dump, DECIMAL, 2)
TRANSFORM (data_hex2, dump, HEXADECIMAL, 2)
TRANSFORM (data_oct4, dump, OCTAL, 4)
TRANSFORM (data_dec4, dump, DECIMAL, 4)
TRANSFORM (data_hex4, dump, HEXADECIMAL, 4)

TRANSFORM (oct1_data, undump, OCTAL, 1)
TRANSFORM (dec1_data, undump, DECIMAL, 1)
TRANSFORM (hex1_data, undump, HEXADECIMAL, 1)
TRANSFORM (oct2_data, undump, OCTAL, 2)
TRANSFORM (dec2_data, undump, DECIMAL, 2)
TRANSFORM (hex2_data, undump, HEXADECIMAL, 2)
TRANSFORM (oct4_data, undump, OCTAL, 4)
TRANSFORM (dec4_data, undump, DECIMAL, 4)
TRANSFORM (hex4_data, undump, HEXADECIMAL, 4)

bool
module_dump (RECODE_OUTER outer)
{
  /* Single bytes.  */

  if (!declare_single (outer, "data", "Octal-1",
		       outer->quality_variable_to_variable,
		       NULL, data_oct1))
    return false;
  if (!declare_single (outer, "data", "Decimal-1",
		       outer->quality_variable_to_variable,
		       NULL, data_dec1))
    return false;
  if (!declare_single (outer, "data", "Hexadecimal-1",
		       outer->quality_variable_to_variable,
		       NULL, data_hex1))
    return false;
  if (!declare_single (outer, "Octal-1", "data",
		       outer->quality_variable_to_variable,
		       NULL, oct1_data))
    return false;
  if (!declare_single (outer, "Decimal-1", "data",
		       outer->quality_variable_to_variable,
		       NULL, dec1_data))
    return false;
  if (!declare_single (outer, "Hexadecimal-1", "data",
		       outer->quality_variable_to_variable,
		       NULL, hex1_data))
    return false;

  if (!declare_alias (outer, "o1", "Octal-1"))
    return false;
  if (!declare_alias (outer, "d1", "Decimal-1"))
    return false;
  if (!declare_alias (outer, "x1", "Hexadecimal-1"))
    return false;
  if (!declare_alias (outer, "o", "Octal-1"))
    return false;
  if (!declare_alias (outer, "d", "Decimal-1"))
    return false;
  if (!declare_alias (outer, "x", "Hexadecimal-1"))
    return false;

  /* Double bytes.  */

  if (!declare_single (outer, "data", "Octal-2",
		       outer->quality_variable_to_variable,
		       NULL, data_oct2))
    return false;
  if (!declare_single (outer, "data", "Decimal-2",
		       outer->quality_variable_to_variable,
		       NULL, data_dec2))
    return false;
  if (!declare_single (outer, "data", "Hexadecimal-2",
		       outer->quality_variable_to_variable,
		       NULL, data_hex2))
    return false;
  if (!declare_single (outer, "Octal-2", "data",
		       outer->quality_variable_to_variable,
		       NULL, oct2_data))
    return false;
  if (!declare_single (outer, "Decimal-2", "data",
		       outer->quality_variable_to_variable,
		       NULL, dec2_data))
    return false;
  if (!declare_single (outer, "Hexadecimal-2", "data",
		       outer->quality_variable_to_variable,
		       NULL, hex2_data))
    return false;

  if (!declare_alias (outer, "o2", "Octal-2"))
    return false;
  if (!declare_alias (outer, "d2", "Decimal-2"))
    return false;
  if (!declare_alias (outer, "x2", "Hexadecimal-2"))
    return false;

  /* Quadruple bytes.  */

  if (!declare_single (outer, "data", "Octal-4",
		       outer->quality_variable_to_variable,
		       NULL, data_oct4))
    return false;
  if (!declare_single (outer, "data", "Decimal-4",
		       outer->quality_variable_to_variable,
		       NULL, data_dec4))
    return false;
  if (!declare_single (outer, "data", "Hexadecimal-4",
		       outer->quality_variable_to_variable,
		       NULL, data_hex4))
    return false;
  if (!declare_single (outer, "Octal-4", "data",
		       outer->quality_variable_to_variable,
		       NULL, oct4_data))
    return false;
  if (!declare_single (outer, "Decimal-4", "data",
		       outer->quality_variable_to_variable,
		       NULL, dec4_data))
    return false;
  if (!declare_single (outer, "Hexadecimal-4", "data",
		       outer->quality_variable_to_variable,
		       NULL, hex4_data))
    return false;

  if (!declare_alias (outer, "o4", "Octal-4"))
    return false;
  if (!declare_alias (outer, "d4", "Decimal-4"))
    return false;
  if (!declare_alias (outer, "x4", "Hexadecimal-4"))
    return false;

  return true;
}
