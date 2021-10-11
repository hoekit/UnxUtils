/* Conversion of files between different charsets and surfaces.
   Copyright � 1996, 97, 98, 99 Free Software Foundation, Inc.
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
#include "hash.h"

/*------------------------.
| Produce test patterns.  |
`------------------------*/

/* One should _remove_ pseudo-surfaces to _produce_ test patterns.  This
   strange-looking decision comes from the fact that test patterns are usually
   requested from the `before' position in the request.  */

static bool
test7_data (RECODE_CONST_STEP step, RECODE_TASK task)
{
  unsigned counter;
  int value;

  for (counter = 0; counter < 1 << 7; counter++)
    put_byte (counter, task);

  /* Copy the rest verbatim.  */
  while (value = get_byte (task), value != EOF)
    put_byte (value, task);

  TASK_RETURN (task);
}

static bool
test8_data (RECODE_CONST_STEP step, RECODE_TASK task)
{
  unsigned counter;
  int value;

  for (counter = 0; counter < 1 << 8; counter++)
    put_byte (counter, task);

  /* Copy the rest verbatim.  */
  while (value = get_byte (task), value != EOF)
    put_byte (value, task);

  TASK_RETURN (task);
}

static bool
test15_data (RECODE_CONST_STEP step, RECODE_TASK task)
{
  unsigned counter;
  unsigned value;

  put_ucs2 (BYTE_ORDER_MARK, task);

  /* Before surrogate area.  */
  for (counter = 0; counter < 0xDC00; counter++)
    put_ucs2 (counter, task);
  /* After surrogate area.  */
  for (counter = 0xE000; counter < 1 << 16; counter++)
    switch (counter)
      {
      case BYTE_ORDER_MARK:
      case REPLACEMENT_CHARACTER:
      case BYTE_ORDER_MARK_SWAPPED:
      case NOT_A_CHARACTER:
	break;

      default:
	put_ucs2 (counter, task);
      }

  /* Copy the rest verbatim.  */
  while (value = get_byte (task), value != EOF)
    put_byte (value, task);

  TASK_RETURN (task);
}

static bool
test16_data (RECODE_CONST_STEP step, RECODE_TASK task)
{
  unsigned counter;
  unsigned value;

  for (counter = 0; counter < 1 << 16; counter++)
    put_ucs2 (counter, task);

  /* Copy the rest verbatim.  */
  while (value = get_byte (task), value != EOF)
    put_byte (value, task);

  TASK_RETURN (task);
}

/*-----------------------------------------------.
| Produce frequency count for UCS-2 characters.  |
`-----------------------------------------------*/

struct ucs2_to_count
  {
    recode_ucs2 code;		/* UCS-2 value */
    unsigned count;		/* corresponding count */
  };

static unsigned
ucs2_to_count_hash (const void *void_data, unsigned table_size)
{
  const struct ucs2_to_count *data = void_data;

  return data->code % table_size;
}

static bool
ucs2_to_count_compare (const void *void_first, const void *void_second)
{
  const struct ucs2_to_count *first = void_first;
  const struct ucs2_to_count *second = void_second;

  return first->code == second->code;
}

static int
compare_item (const void *void_first, const void *void_second)
{
  struct ucs2_to_count *const *first = void_first;
  struct ucs2_to_count *const *second = void_second;

  return (*first)->code - (*second)->code;
}

static bool
produce_count (RECODE_CONST_STEP step, RECODE_TASK task)
{
  RECODE_OUTER outer = task->request->outer;
  Hash_table *table;		/* hash table for UCS-2 characters */
  unsigned character;		/* current character being counted */
  size_t size;			/* number of different characters */
  struct ucs2_to_count **array;	/* array into hash table items */
  struct ucs2_to_count **cursor;

  table = hash_initialize (0, NULL,
			   ucs2_to_count_hash, ucs2_to_count_compare, NULL);
  if (!table)
    return false;

  /* Count characters.  */

  while (get_ucs2 (&character, step, task))
    {
      struct ucs2_to_count lookup;
      struct ucs2_to_count *entry;

      lookup.code = character;
      entry = hash_lookup (table, &lookup);
      if (entry)
	entry->count++;
      else
	{
	  if (!ALLOC (entry, 1, struct ucs2_to_count))
	    return false;
	  entry->code = character;
	  entry->count = 1;
	  if (!hash_insert (table, entry))
	    return false;
	}
    }

  /* Sort results.  */

  size = hash_get_n_entries (table);

  if (!ALLOC (array, size, struct ucs2_to_count *))
    return false;
  hash_get_entries (table, (void **) array, size);

  qsort (array, size, sizeof (struct ucs2_to_count *), compare_item);

  /* Produce the report.  */

  {
    const unsigned non_count_width = 12;
    char buffer[50];
    struct ucs2_to_count **cursor;
    unsigned count_width;
    unsigned maximum_count = 0;
    unsigned column = 0;
    unsigned delayed = 0;

    for (cursor = array; cursor < array + size; cursor++)
      if ((*cursor)->count > maximum_count)
	maximum_count = (*cursor)->count;
    sprintf (buffer, "%d", maximum_count);
    count_width = strlen (buffer);

    for (cursor = array; cursor < array + size; cursor++)
      {
	unsigned character = (*cursor)->code;
	const char *mnemonic = ucs2_to_rfc1345 (character);

	if (column + count_width + non_count_width > 80)
	  {
	    putchar ('\n');
	    delayed = 0;
	    column = 0;
	  }
	else
	  while (delayed)
	    {
	      putchar (' ');
	      delayed--;
	    }

	printf ("%*d  %.4X", count_width, (*cursor)->count, character);
	if (mnemonic)
	  {
	    putchar (' ');
	    fputs (mnemonic, stdout);
	    delayed = 6 - 1 - strlen (mnemonic);
	  }
	else
	  delayed = 6;

	column += count_width + non_count_width;
      }

    if (column)
      putchar ('\n');
  }

  /* Clean-up.  */

  {
    struct ucs2_to_count **cursor;

    for (cursor = array; cursor < array + size; cursor++)
      free (*cursor);
  }
  hash_free (table);

  TASK_RETURN (task);
}

/*---------------------------.
| Fully dump an UCS-2 file.  |
`---------------------------*/

static bool
produce_full_dump (RECODE_CONST_STEP step, RECODE_TASK task)
{
  unsigned character;		/* character to dump */
  const char *charname;		/* charname for code */
  bool french;			/* if output should be in French */
  const char *string;		/* environment value */

  /* Decide if we prefer French or English output.  */

  french = false;
  string = getenv ("LANGUAGE");
  if (string && string[0] == 'f' && string[1] == 'r')
    french = true;
  else
    {
      string = getenv ("LANG");
      if (string && string[0] == 'f' && string[1] == 'r')
	french = true;
    }

  /* Dump all characters.  */

  fputs (_("UCS2   Mne   Description\n\n"), stdout);

  while (get_ucs2 (&character, step, task))
    {
      const char *mnemonic = ucs2_to_rfc1345 (character);

      printf ("%.4X", character);
      if (mnemonic)
	printf ("   %-3s", mnemonic);
      else
	fputs ("      ", stdout);

      if (french)
	{
	  charname = ucs2_to_french_charname (character);
	  if (!charname)
	    charname = ucs2_to_charname (character);
	}
      else
	{
	  charname = ucs2_to_charname (character);
	  if (!charname)
	    charname = ucs2_to_french_charname (character);
	}

      if (charname)
	{
	  fputs ("   ", stdout);
	  fputs (charname, stdout);
	}
      printf ("\n");
    }

  TASK_RETURN (task);
}

/*-----------------------------------------.
| Declare charsets, surfaces and aliases.  |
`-----------------------------------------*/

bool
module_debug (RECODE_OUTER outer)
{
  /* Test surfaces.  */

  if (!declare_single (outer, "test7", "data",
		       outer->quality_variable_to_byte,
		       NULL, test7_data))
    return false;
  if (!declare_single (outer, "test8", "data",
		       outer->quality_variable_to_byte,
		       NULL, test8_data))
    return false;
  if (!declare_single (outer, "test15", "data",
		       outer->quality_variable_to_ucs2,
		       NULL, test15_data))
    return false;
  if (!declare_single (outer, "test16", "data",
		       outer->quality_variable_to_ucs2,
		       NULL, test16_data))
    return false;

  /* Analysis charsets.  */

  if (!declare_single (outer, "ISO-10646-UCS-2", "count-characters",
		       outer->quality_ucs2_to_variable,
		       NULL, produce_count))
    return false;
  if (!declare_single (outer, "ISO-10646-UCS-2", "dump-with-names",
		       outer->quality_ucs2_to_variable,
		       NULL, produce_full_dump))
    return false;

  return true;
}
