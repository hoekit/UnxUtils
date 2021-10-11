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

static bool
permute_21 (RECODE_CONST_STEP step, RECODE_TASK task)
{
  int character1;
  int character2;

  while (true)
    {
      character1 = get_byte (task);
      if (character1 == EOF)
	break;

      character2 = get_byte (task);
      if (character2 == EOF)
	{
	  put_byte (character1, task);
	  break;
	}

      put_byte (character2, task);
      put_byte (character1, task);
    }

  TASK_RETURN (task);
}

static bool
permute_4321 (RECODE_CONST_STEP step, RECODE_TASK task)
{
  int character1;
  int character2;
  int character3;
  int character4;

  while (true)
    {
      character1 = get_byte (task);
      if (character1 == EOF)
	break;

      character2 = get_byte (task);
      if (character2 == EOF)
	{
	  put_byte (character1, task);
	  break;
	}

      character3 = get_byte (task);
      if (character3 == EOF)
	{
	  put_byte (character2, task);
	  put_byte (character1, task);
	  break;
	}

      character4 = get_byte (task);
      if (character4 == EOF)
	{
	  put_byte (character3, task);
	  put_byte (character2, task);
	  put_byte (character1, task);
	  break;
	}

      put_byte (character4, task);
      put_byte (character3, task);
      put_byte (character2, task);
      put_byte (character1, task);
    }

  TASK_RETURN (task);
}

bool
module_permutations (RECODE_OUTER outer)
{
  return
    declare_single (outer, "data", "21-Permutation",
		    outer->quality_variable_to_variable,
		    NULL, permute_21)
    && declare_single (outer, "21-Permutation", "data",
		       outer->quality_variable_to_variable,
		       NULL, permute_21)
    && declare_single (outer, "data", "4321-Permutation",
		       outer->quality_variable_to_variable,
		       NULL, permute_4321)
    && declare_single (outer, "4321-Permutation", "data",
		       outer->quality_variable_to_variable,
		       NULL, permute_4321)
    && declare_alias (outer, "swabytes", "21-Permutation");
}
