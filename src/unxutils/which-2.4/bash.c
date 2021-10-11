/*
 * Copyright (C) 1987 - 1999 Free Software Foundation, Inc.
 *
 * This file is based on stuff from GNU Bash 1.14.7, the Bourne Again SHell.
 * Everything that was changed is marked with the word `CHANGED'.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#include "sys.h"
#include <sys/stat.h>
#include "bash.h"

/* bash uses GID_T, autoconf defines GETGROUPS_T */
#define GID_T GETGROUPS_T

/*
 * CHANGED:
 * Perhaps these need new configure.in entries.
 * The following macro's are used in bash, and below:
 */
#define HAVE_GETGROUPS
#undef SHELL
#undef AFS
#undef NOGROUP

/*
 * CHANGED:
 * - Added prototypes,
 * - used ANSI function arguments,
 * - made all functions static and
 * - changed all occurences of 'char *' into 'const char *' where possible.
 * - exported functions needed in which.c
 */
static int group_member (GID_T gid);
static char *extract_colon_unit (const char *string, int *p_index);

/*===========================================================================
 *
 * Almost everything below is from execute_cmd.c from bash-1.14.7,
 * a few functions are from other files: test.c, general.c and variables.c.
 *
 */

#if defined (HAVE_GETGROUPS)
/* The number of groups that this user is a member of. */
static int ngroups = 0;
static GID_T *group_array = (GID_T *)NULL;
static int default_group_array_size = 0;
#endif /* HAVE_GETGROUPS */

#if !defined (NOGROUP)
#  define NOGROUP (GID_T) -1
#endif

/* Return non-zero if GID is one that we have in our groups list. */
static int
group_member (GID_T gid)
{
  static GID_T pgid = (GID_T)NOGROUP;
  static GID_T egid = (GID_T)NOGROUP;

  if (pgid == (GID_T)NOGROUP)
#if defined (SHELL)
    pgid = (GID_T) current_user.gid;
#else /* !SHELL */
    pgid = (GID_T) getgid ();
#endif /* !SHELL */

  if (egid == (GID_T)NOGROUP)
#if defined (SHELL)
    egid = (GID_T) current_user.egid;
#else /* !SHELL */
    egid = (GID_T) getegid ();
#endif /* !SHELL */

  if (gid == pgid || gid == egid)
    return (1);

#if defined (HAVE_GETGROUPS)
  /* getgroups () returns the number of elements that it was able to
     place into the array.  We simply continue to call getgroups ()
     until the number of elements placed into the array is smaller than
     the physical size of the array. */

  while (ngroups == default_group_array_size)
    {
      default_group_array_size += 64;

      group_array = (GID_T *)
        xrealloc (group_array, default_group_array_size * sizeof (GID_T));

      ngroups = getgroups (default_group_array_size, group_array);
    }

  /* In case of error, the user loses. */
  if (ngroups < 0)
    return (0);

  /* Search through the list looking for GID. */
  {
    register int i;

    for (i = 0; i < ngroups; i++)
      if (gid == group_array[i])
        return (1);
  }
#endif /* HAVE_GETGROUPS */

  return (0);
}

#define u_mode_bits(x) (((x) & 0000700) >> 6)
#define g_mode_bits(x) (((x) & 0000070) >> 3)
#define o_mode_bits(x) (((x) & 0000007) >> 0)
#define X_BIT(x) ((x) & 1)

/* Return some flags based on information about this file.
   The EXISTS bit is non-zero if the file is found.
   The EXECABLE bit is non-zero the file is executble.
   Zero is returned if the file is not found. */
int
file_status (const char *name)
{
  struct stat finfo;
  static int user_id = -1;

  /* Determine whether this file exists or not. */
  if (stat (name, &finfo) < 0)
    return (0);

  /* If the file is a directory, then it is not "executable" in the
     sense of the shell. */
  if (S_ISDIR (finfo.st_mode))
    return (FS_EXISTS);

#if defined (AFS)
  /* We have to use access(2) to determine access because AFS does not
     support Unix file system semantics.  This may produce wrong
     answers for non-AFS files when ruid != euid.  I hate AFS. */
  if (access (name, X_OK) == 0)
    return (FS_EXISTS | FS_EXECABLE);
  else
    return (FS_EXISTS);
#else /* !AFS */

  /* Find out if the file is actually executable.  By definition, the
     only other criteria is that the file has an execute bit set that
     we can use. */
  if (user_id == -1)
    user_id = geteuid (); /* CHANGED: bash uses: current_user.euid; */

  /* Root only requires execute permission for any of owner, group or
     others to be able to exec a file. */
  if (user_id == 0)
    {
      int bits;

      bits = (u_mode_bits (finfo.st_mode) |
              g_mode_bits (finfo.st_mode) |
              o_mode_bits (finfo.st_mode));

      if (X_BIT (bits))
        return (FS_EXISTS | FS_EXECABLE);
    }

  /* If we are the owner of the file, the owner execute bit applies. */
  if (user_id == finfo.st_uid && X_BIT (u_mode_bits (finfo.st_mode)))
    return (FS_EXISTS | FS_EXECABLE);

  /* If we are in the owning group, the group permissions apply. */
  if (group_member (finfo.st_gid) && X_BIT (g_mode_bits (finfo.st_mode)))
    return (FS_EXISTS | FS_EXECABLE);

  /* If `others' have execute permission to the file, then so do we,
     since we are also `others'. */
  if (X_BIT (o_mode_bits (finfo.st_mode)))
    return (FS_EXISTS | FS_EXECABLE);
  else
    return (FS_EXISTS);
#endif /* !AFS */
}

/* Return 1 if STRING is an absolute program name; it is absolute if it
   contains any slashes.  This is used to decide whether or not to look
   up through $PATH. */
int
absolute_program (const char *string)
{
  return ((char *)strchr (string, DIRSEP) != (char *)NULL);
}

/* Given a string containing units of information separated by colons,
   return the next one pointed to by (P_INDEX), or NULL if there are no more.
   Advance (P_INDEX) to the character after the colon. */
char *
extract_colon_unit (const char *string, int *p_index)
{
  int i, start;

  i = *p_index;

  if (!string || (i >= (int)strlen (string)))
    return ((char *)NULL);

  /* Each call to this routine leaves the index pointing at a colon if
     there is more to the path.  If I is > 0, then increment past the
     `:'.  If I is 0, then the path has a leading colon.  Trailing colons
     are handled OK by the `else' part of the if statement; an empty
     string is returned in that case. */
  if (i && string[i] == PATHSEP)
    i++;

  start = i;

  while (string[i] && string[i] != PATHSEP) i++;

  *p_index = i;

  if (i == start)
    {
      if (string[i])
        (*p_index)++;

      /* Return "" in the case of a trailing `:'. */
      return (savestring (""));
    }
  else
    {
      char *value;

      value = xmalloc (1 + i - start);
      strncpy (value, string + start, i - start);
      value [i - start] = '\0';

      return (value);
    }
}

/* Return the next element from PATH_LIST, a colon separated list of
   paths.  PATH_INDEX_POINTER is the address of an index into PATH_LIST;
   the index is modified by this function.
   Return the next element of PATH_LIST or NULL if there are no more. */
char *
get_next_path_element (const char *path_list, int *path_index_pointer)
{
  char *path;

  path = extract_colon_unit (path_list, path_index_pointer);

  if (!path)
    return (path);

  if (!*path)
    {
      free (path);
      path = savestring (".");
    }

  return (path);
}

/* Turn PATH, a directory, and NAME, a filename, into a full pathname.
   This allocates new memory and returns it. */
char *
make_full_pathname (const char *path, const char *name, int name_len)
{
  char *full_path;
  int path_len;

  path_len = strlen (path);
  full_path = (char *) xmalloc (2 + path_len + name_len);
  strcpy (full_path, path);
  full_path[path_len] = DIRSEP;
  strcpy (full_path + path_len + 1, name);
  return (full_path);
}

#ifdef WIN32
int getgid() {return -1;}
int getegid() {return -1;}
int geteuid() {return -1;}
int getgroups() {return -1;}
#endif