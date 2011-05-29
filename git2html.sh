#! /bin/bash

# git2html - Convert a git repository to a set of static HTML pages.
# Copyright (c) 2011 Neal H. Walfield <neal@walfield.org>
#
# git2html is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# git2html is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -e
set -o pipefail
# set -x

usage()
{
  echo "Usage $0 [-prlbq] TARGET"
  echo "Generate static HTML pages in TARGET for the specified git repository."
  echo
  echo "  -p  Project's name"
  echo "  -r  Repository to clone from."
  echo "  -l  Public repository link, e.g., 'http://host.org/project.git'"
  echo "  -b  List of branches to process (default: all)."
  echo "  -q  Be quiet."
  echo "  -f  Force rebuilding of all pages."
  exit $1
}

show_progress=1
force_rebuild=0

progress()
{
  if test x"$show_progress" = x1
  then
    echo "$@"
  fi
}

while getopts ":p:r:l:b:qf" opt
do
  case $opt in
    p)
      PROJECT=$OPTARG
      ;;
    r)
      # Directory containing the repository.
      REPOSITORY=$OPTARG
      ;;
    l)
      PUBLIC_REPOSITORY=$OPTARG
      ;;
    b)
      BRANCHES=$OPTARG
      ;;
    q)
      show_progress=0
      ;;
    f)
      force_rebuild=1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
  esac
done
shift $(($OPTIND - 1))

if test $# -ne 1
then
  usage 1
fi

# Where to create the html pages.
TARGET="$1"

# Make sure the target exists.
mkdir -p "$TARGET"

CONFIG_FILE=".ht_git2html"

# Read the configuration file.
if test -e "$TARGET/$CONFIG_FILE"
then
  . "$TARGET/$CONFIG_FILE"
fi

if test x"$REPOSITORY" = x
then
  echo "-r required."
  usage 1
fi

# The output version
CURRENT_TEMPLATE="$(sha1sum "$0")"
if test "x$CURRENT_TEMPLATE" != "x$TEMPLATE"
then
  progress "Rebuilding all pages as output template changed."
  force_rebuild=1
fi
TEMPLATE="$CURRENT_TEMPLATE"

{
  save()
  {
    # Prefer environment variables and arguments to the configuration file.
    echo "$1=\"\${$1:-\"$2\"}\""
  }
  save "PROJECT" "$PROJECT"
  save "REPOSITORY" "$REPOSITORY"
  save "PUBLIC_REPOSITORY" "$PUBLIC_REPOSITORY"
  save "TARGET" "$TARGET"
  save "BRANCHES" "$BRANCHES"
  save "TEMPLATE" "$TEMPLATE"
} > "$TARGET/$CONFIG_FILE"

if test ! -d "$REPOSITORY"
then
  echo "Repository \"$REPOSITORY\" does not exists.  Misconfiguration likely."
  exit 1
fi

html_header()
{
  title="$1"
  top_level="$2"

  if test x"$PROJECT" != x -a x"$title" != x
  then
    # Title is not the empty string.  Prefix it with ": "
    title=": $title"
  fi

  echo "<html><head><title>$PROJECT$title</title></head>" \
    "<body>" \
    "<h1><a href=\"$top_level\">$PROJECT</a>$title</h1>"
}

html_footer()
{
  echo "<hr>" \
    "Generated by" \
    "<a href=\"http://hssl.cs.jhu.edu/~neal/git2html\">git2html</a>."
}

# Ensure that some directories we need exist.
if test x"$force_rebuild" = x1
then
  rm -rf "$TARGET/objects" "$TARGET/commits"
fi

if test ! -d "$TARGET/objects"
then
  mkdir "$TARGET/objects"
fi

if test ! -e "$TARGET/commits"
then
  mkdir "$TARGET/commits"
fi

if test ! -e "$TARGET/branches"
then
  mkdir "$TARGET/branches"
fi

unset GIT_DIR

# Get an up-to-date copy of the repository.
if test ! -e "$TARGET/repository"
then
  # Clone the repository.
  git clone "$REPOSITORY" "$TARGET/repository"
fi

cd "$TARGET/repository"

# git mrge fails if there are not set.  Fake them.
git config user.email "git2html@git2html"
git config user.name "git2html"

first=""
for branch in ${BRANCHES:-$(git branch --no-color -r \
                              | sed 's#^ *origin/##; s/HEAD//')}
do
  if test x"$first" = x
  then
    first=$branch
  fi

  # Don't use grep -v as that returns 1 if there is no output.
  git fetch "$REPOSITORY" ${branch} \
      | gawk '/^Already up-to-date[.]$/ { skip=1; }
              { if (! skip) print; skip=0 }'
  if ! git branch -l | egrep "^[* ] $branch\$" 
  then
    git checkout origin/$branch
    git branch $branch
  fi
  git checkout $branch
  git merge FETCH_HEAD
done
git checkout $first



if test x"$BRANCHES" = x
then
  BRANCHES=$(git branch --no-color -l | sed 's/^..//')
fi

# For each branch and each commit create and extract an archive of the form
#   $TARGET/commits/$commit
#
# and a link:
#
#   $TARGET/branches/$commit -> $TARGET/commits/$commit

# Count the number of branch we want to process to improve reporting.
bcount=0
for branch in $BRANCHES
do
  let ++bcount
done

INDEX="$TARGET/index.html"

{
  html_header
  echo "<h2>Repository</h2>"

  if test x"$PUBLIC_REPOSITORY" != x
  then
    echo  "Clone this repository using:" \
      "<pre>" \
      " git clone $PUBLIC_REPOSITORY" \
      "</pre>"
  fi

  echo "<h3>Branches</h3>" \
    "<ul>"
} > "$INDEX"

b=0
for branch in $BRANCHES
do
  let ++b

  cd "$TARGET/repository"

  COMMITS=$(mktemp)
  git rev-list --graph $branch > $COMMITS

  # Count the number of commits on this branch to improve reporting.
  ccount=$(egrep '[0-9a-f]' < $COMMITS | wc -l)

  progress "Branch $branch ($b/$bcount): processing ($ccount commits)."

  BRANCH_INDEX="$TARGET/branches/$branch.html"

  c=0
  while read -r commitline
  do
    # See http://www.itnewb.com/unicode
    graph=$(echo "$commitline" \
            | sed 's/ [0-9a-f]*$//; s/|/\&#x2503;/g; s/[*]/\&#x25CF;/g;
                   s/[\]/\&#x2B0A;/g; s/\//\&#x2B0B;/g;')
    commit=$(echo "$commitline" | sed 's/^[^0-9a-f]*//')

    if test x"$commit" = x
    then
      # This is just a bit of graph.  Add it to the branch's
      # index.html and then go to the next commit.
      echo "<tr><td valign=\"middle\"><pre>$graph</pre></td><td></td><td></td><td></td></tr>" \
	>> "$BRANCH_INDEX"
      continue
    fi

    let ++c
    progress "Commit $commit ($c/$ccount): processing."

    # Extract metadata about this commit.
    metadata=$(git log -n 1 --pretty=raw $commit \
        | sed 's#<#\&lt;#g; s#>#\&gt;#g; ')
    parent=$(echo "$metadata" \
	| gawk '/^parent / { $1=""; sub (" ", ""); print $0 }')
    committer=$(echo "$metadata" \
	| gawk '/^committer / { NF=NF-2; $1=""; sub(" ", ""); print $0 }')
    date=$(echo "$metadata" | gawk '/^committer / { print $(NF=NF-1); }')
    date=$(date -u -d "1970-01-01 $date sec")
    log=$(echo "$metadata" | gawk '/^    / { if (!done) print $0; done=1; }')
    loglong=$(echo "$metadata" | gawk '/^    / { print $0; }')

    if test "$c" = "1"
    then
      # This commit is the current head of the branch.

      # Update the branch's link.
      ln -sf "../commits/$commit" "$TARGET/branches/$branch"

      # Update the project's index.html and the branch's index.html.
      echo "<li><a href=\"branches/$branch.html\">$branch</a> " \
        "$log $committer $date" >> "$INDEX"

      {
        html_header "Branch: $branch" ".."
        echo "<table>"
      } > "$BRANCH_INDEX"
    fi

    # Add this commit to the branch's index.html.
    echo "<tr><td valign=\"middle\"><pre>$graph</pre></td><td><a href=\"../commits/$commit\">$log</a></td><td>$committer</td><td>$date</td></tr>" \
	>> "$BRANCH_INDEX"


    # Commits don't change.  If the directory already exists, it is up
    # to date and we can save some work.
    COMMIT_BASE="$TARGET/commits/$commit"
    if test -e "$COMMIT_BASE"
    then
      progress "Commit $commit ($c/$ccount): already processed."
      continue
    fi

    mkdir "$COMMIT_BASE"

    # Get the list of files in this commit.
    FILES=$(mktemp)
    git ls-tree -r "$commit" > "$FILES"

    # Create the commit's index.html: the metadata, a summary of the changes
    # and a list of all the files.
    COMMIT_INDEX="$COMMIT_BASE/index.html"
    {
      html_header "Commit: $commit" "../.."

      # The metadata.
      echo "<h2>Branch: <a href=\"../../branches/$branch.html\">$branch</a></h2>" \
	"<p>Committer: $committer" \
	"<br>Date: $date"
      for p in $parent
      do
        echo "<br>Parent: <a href=\"../../commits/$p\">$p</a>" \
	" (<a href=\"../../commits/$commit/diff-to-$p.html\">diff to parent</a>)"
      done
      echo "<br>Log message:" \
	"<p><pre>$loglong</pre>"
      for p in $parent
      do
	echo "<br>Diff Stat to $p:" \
	  "<blockquote><pre>"
        git diff --stat $p..$commit \
          | gawk \
              '{ if (last_line) print last_line;
                 last_line_raw=$0;
                 $1=sprintf("<a href=\"%s.raw.html\">%s</a>" \
                            "(<a href=\"../../commits/'"$p"'/%s.raw.html\">old</a>)" \
                            "%*s" \
                            "(<a href=\"diff-to-'"$p"'.html#%s\">diff</a>)",
                            $1, $1, $1, 60 - length ($1), " ", $1);
                    last_line=$0; }
                  END { print last_line_raw; }'
        echo "</pre></blockquote>"
      done
      echo "<p>Files:" \
        "<ul>"

      # The list of files as a hierarchy.
      gawk 'function spaces(l) {
             for (space = 1; space <= l; space ++) { printf ("  "); }
           }
           function max(a, b) { if (a > b) { return a; } return b; }
           function min(a, b) { if (a < b) { return a; } return b; }
           BEGIN {
             current_components[1] = "";
             delete current_components[1];
           }
           {
             file=$4;
             split(file, components, "/")
             # Remove the file.  Keep the directories.
             file=components[length(components)]
             delete components[length(components)];
  
             # See if a path component changed.
             for (i = 1;
                  i <= min(length(components), length(current_components));
                  i ++)
             {
               if (current_components[i] != components[i])
               # It did.
               {
                 last=length(current_components);
                 for (j = last; j >= i; j --)
                 {
                   spaces(j);
                   printf ("</ul> <!-- %s -->\n", current_components[j]);
                   delete current_components[j];
                 }
               }
             }
  
             # See if there are new path components.
             for (; i <= length(components); i ++)
             {
                 current_components[i] = components[i];
                 spaces(i);
                 printf("<li>%s\n", components[i]);
                 spaces(i);
                 printf("<ul>\n");
             }
  
             spaces(length(current_components))
             printf ("<li><a href=\"%s.raw.html\">%s</a>\n", $4, file);
           }' < "$FILES"

      echo "</ul>"
      html_footer
    } > "$COMMIT_INDEX"

    # Create the commit's diff-to-parent.html file.
    for p in $parent
    do
      {
        html_header "diff $(echo $commit | sed 's/^\(.\{8\}\).*/\1/') $(echo $p | sed 's/^\(.\{8\}\).*/\1/')" "../.."
        echo "<h2>Branch: <a href=\"../../branches/$branch.html\">$branch</a></h2>" \
          "<h3>Commit: <a href=\"index.html\">$commit</a></h3>" \
  	"<p>Committer: $committer" \
  	"<br>Date: $date" \
  	"<br>Parent: <a href=\"../$p\">$p</a>" \
  	"<br>Log message:" \
  	"<p><pre>$loglong</pre>" \
  	"<p>" \
          "<pre>"
        git diff $p..$commit \
          | sed 's#<#\&lt;#g; s#>#\&gt;#g; ' \
  	| gawk '/^diff --git/ {
                    file=$3;
                    sub (/^a\//, "", file);
                    $3=sprintf("<a name=\"%s\">%s</a>", file, $3);
                  }
                  { ++line; printf("%5d: %s\n", line, $0); }'
        echo "</pre>"
        html_footer
      } > "$COMMIT_BASE/diff-to-$p.html"
    done


    # For each file in the commit, ensure the object exists.
    while read -r line
    do
      file_base=$(echo "$line" | gawk '{ print $4 }')
      file="$TARGET/commits/$commit/$file_base"
      sha=$(echo "$line" | gawk '{ print $3 }')

      object_dir="$TARGET/objects/"$(echo "$sha" \
	  | sed 's#^\([a-f0-9]\{2\}\).*#\1#')
      object="$object_dir/$sha"

      if test ! -e "$object"
      then
        # File does not yet exists in the object repository.
        # Create it.
	if test ! -d "$object_dir"
	then
	  mkdir "$object_dir"
	fi

        # The object's file should not be commit or branch specific:
        # the same html is shared among all files with the same
        # content.
        {
          html_header "$sha"
          echo "<pre>"
          git show "$sha" \
            | sed 's#<#\&lt;#g; s#>#\&gt;#g; ' \
            | gawk '{ ++line; printf("%6d: %s\n", line, $0); }'
          echo "</pre>"
          html_footer
        } > "$object"
      fi

      # Create a hard link to the file in the object repository.
      mkdir -p $(dirname "$file")
      ln "$object" "$file.raw.html"
    done <"$FILES"
    rm -f "$FILES"
  done <$COMMITS
  rm -f $COMMITS

  {
    echo "</table>"
    html_footer
  } >> "$BRANCH_INDEX"
done

{
  echo "</ul>"
  html_footer
} >> "$INDEX"

