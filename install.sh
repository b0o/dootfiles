#!/bin/bash
# shopt -s dotglob
DOTFILESINSTALL=true
BASEDIR=$(dirname $0)

# load dootfiles configuration
# Can define the following configuration options:
#    $INSTALLDIR  - Directory to install (link) doots into - usually $HOME
#    $DOTFILEDIR  - Path to the dootfiles repository (e.g. the directory containing this file)
#    $BINDIR      - Path to the directory containing binaries and scripts. $DOTFILEDIR/bin by default
#    $VENDORDIR   - Directory which will contain third-party git repos from $VENDORREPOS
#    $VENDORREPOS - An array of git repository URLs for third-party dependencies.
#                   If the scheme + domain (i.e. "https://example.com/") is omitted, it will
#                   default to "https://github.com/", e.g "username/repo" will refer
#                   to "https://github.com/username/repo".
#                   If, once cloned, the repository contains an executable file named "install.dotfiles.sh"
#                   in the topmost directory, that file will be executed. All environment variables set in this
#                   script will be available to it (e.g. the install.dotfiles.sh script can check for the $DOTFILESINSTALL
#                   variable (declared above) to determine if it was called by this script or not.
source "$BASEDIR/.dootrc"

function log () {
	[[ $quiet ]] && return
	echo "${@}" >&2
}

function log () {
	[[ $quiet ]] && return
	echo "${@}" >&2
}

function vlog () {
	[[ $verbose == 0 ]] && return
	echo "${@}" >&2
}

function logf () {
	[[ $quiet ]] && return
	printf ${@} >&2
}

function vlogf () {
	[[ $verbose == 0 ]] && return
	printf ${@} >&2
}

function backup_file () {
	usage="usage: $(basename "$0"):${FUNCNAME[0]} [-h] [-p] [-e] <path>

	Attempt to back up an existing file to a new location, removing the original

	Options:
		 -h          Display this message and exit.
		 -p          Prompt the user to confirm or decline the backup operation.
		 -e <ext>    The extension to append to the backed up file (default: .bak)
		 -d <dir>    The directory to copy the backup file to (defaults to
		             same parent directory as <path>)
	"
	PROMPT=0
	EXT=".bak"
	DIR=""
	while getopts 'hpe:' option; do
		case "$option" in
			h) log "$usage"
				exit 1
				;;
			p) PROMPT=1;      vlog "-p (PROMPT) set to '${PROMPT}'"
				;;
			e) EXT="$OPTARG"; vlog "-e (EXT) set to '${EXT}'"
				;;
			d) DIR="$OPTARG"; vlog "-d (DIR) set to '${DIR}'"
				;;
			\?) logf "Error: illegal option: -%s\n" "${OPTARG}"
				log "$usage"
				exit 1
				;;
		esac
	done
	shift $(($OPTIND - 1))

	[[ -z $1 ]] && {
		log "Error: Missing argument <file>"
		log "$usage"
		exit 1
	}

	FILE="$1"

	[[ ! -a $FILE ]] && {
		log "Error: $FILE does not exist"
		return 1
	}

	FILENAME="$(basename "$FILE")"

	[[ -z $DIR ]] && {
		DIR="$(dirname $FILE)"
	}

	[[ ! -d $DIR ]] || [[ ! -w $DIR ]] && {
		log "Error: $DIR does not exist or is not writable"
		return 1
	}

	BAKPATH="$DIR/$FILENAME$EXT"

	[[ -e $BAKPATH ]] && {
		vlog "$BAKPATH exists"
		i=0
		p="${BAKPATH}${i}"
		while [[ -e $p ]] ; do
			vlog "$p exists"
			let i++
			p="${BAKPATH}${i}"
			vlog "Testing $p"
		done
		BAKPATH=$p
		vlog "Using $BAKPATH"
	}

	[[ ! -a $FILE ]] && {
		log "Error: $FILE does not exist"
		return 1
	}

	response="a"

	[[ $PROMPT == 1 ]] && {
		msg="Notice: $FILE exists!
		What would you like to do?
			a) Back it up to $BAKPATH and continue installing $FILENAME
			b) Continue without backing up (Overwrite $FILE)
			C) Skip
		Choose: [a/b/C]: "
		read -r -p "$msg" response
	}

	# Back up
	[[ $response =~ ^([aA])$ ]] && {
		log "Backing up $FILE to $BAKPATH"
		cp $FILE $BAKPATH
		[[ $? != 0 ]] && {
			log "Error: Unable to copy $FILE to $BAKPATH"
			return $?
		}
		vlog "Removing original file $FILE after backing up to $BAKPATH"
		rm -rf $FILE
		[[ $? != 0 ]] && {
			log "Error: Unable to remove $FILE after backing up"
			return $?
		}
		return 0
	}

	# Overwrite
	[[ $response =~ ^([bB])$ ]] && {
		log "Overwriting $FILE"
		rm -rf $FILE
		[[ $? != 0 ]] && {
			log "Error: Unable to overwrite $FILE"
			return $?
		}
		return 0
	}

	# Skip
	[[ $response =~ ^([cC])$ ]] || [[ -z $response ]] && {
		log "Skipping $FILE"
		return 1
	}
	log "Invalid response: $response"
	return 1
}

function make_file () {
	vlog "Creating file: ${@}"
	return 0 # TODO
}

function ensure_exists () {
	usage="usage: $(basename "$0"):${FUNCNAME[0]} [-h] [-m] [-p] [-w] [-d|f|l <source>] <path>

	Ensure a file exists at the given path

	Options:
		 -h          Display this message and exit.
		 -m          Create the file if it doesn't exist
		 -p          Recursively check parent(s) are directories first.
		             The values of -m, -p, and -w will be passed along.
		 -w          Ensure file is writable
		 -d          Assert file is a directory.
		             If -m is set and nothing yet exists, an empty directory will be created.
		 -f          Assert file is a normal file (default).
		             If -m is set and nothing yet exists, an empty file will be created.
		 -l <source> Assert file is a symbolic link and points to <source>.
		             If -m is set and nothing yet exists, a symbolic link will be created,
		             pointing to <source>. Fails if either <source> doesn't exist or <path> exists as
		             a symbolic link but doesn't point to <source>, unless -L is specified.
		 -L          Don't ensure that either <source> exists or <path> points to <source> specified in -l.
		 -b          If file exists but is of wrong type (or link points to wrong location),
		             offer to backup the existing file to <path>.bak[#]. Only valid if -m is
		             specified as well.
	"
	TYPE="f"
	MK=0
	PARENT=0
	WRITABLE=0
	LINK=""
	ENSURELINK=1
	BACKUP=0
	while getopts 'hmpwdfl:L' option; do
		case "$option" in
			h) log "$usage"
				exit 1
				;;
			m) MK=1;          vlog "-m (MK) set to '${MK}'"
				;;
			p) PARENT=1;      vlog "-p (PARENT) set to '${PARENT}'"
				;;
			w) WRITABLE=1;    vlog "-w (WRITABLE) set to '${WRITABLE}'"
				;;
			d) TYPE="d";      vlog "-d (TYPE) set to '${TYPE}'"
				;;
			f) TYPE="f";      vlog "-f (TYPE) set to '${TYPE}'"
				;;
			l) TYPE="l";      vlog "-l (TYPE) set to '${TYPE}'"
				LINK="$OPTARG"; vlog "-l (LINK) set to '${LINK}'"
				;;
			L) ENSURELINK=0;  vlog "-L (ENSURELINK) set to '${ENSURELINK}'"
				;;
			b) BACKUP=1;      vlog "-b (BACKUP) set to '${BACKUP}'"
				;;
			\?) logf "Error: illegal option: -%s\n" "${OPTARG}"
				log "$usage"
				exit 1
				;;
		esac
	done
	shift $(($OPTIND - 1))

	[[ $BACKUP == 1 ]] && [[ $MK == 0 ]] && {
		log "Error: -m must be specified with -b"
		log "$usage"
		exit 1
	}

	[[ -z $1 ]] && {
		log "Error: Missing argument <path>"
		log "$usage"
		exit 1
	}

	FILE="$1"

	[[ ! -a $FILE ]] && {
		[[ $MK == 1 ]] && {
			[[ $TYPE == 'l' ]] && [[ $ENSURELINK == 1 ]] && {
				[[ ! -a $LINK ]] && return 1
			}
			make_file "-${TYPE}" $FILE
			return $?
		}
		return 1
	}

	[[ $TYPE == 'd' ]] && {
		[[ -d $FILE ]] && {
			return 0
		} || {
			[[ $BACKUP == 1 ]] && {
				backup_file -p $FILE
				[[ $? != 0 ]] && return 1
				make_file -d $FILE
				return $?
			}
			return 1
		}
	}

	[[ $TYPE == 'f' ]] && {
		[[ -f $FILE ]] && {
			return 0
		} || {
			[[ $BACKUP == 1 ]] && {
				backup_file -p $FILE
				[[ $? != 0 ]] && return 1
				make_file -f $FILE
				return $?
			}
			return 1
		}
	}

	[[ $TYPE == 'l' ]] && {
		[[ -L $FILE ]] &&  {
			[[ $ENSURELINK == 1 ]] && {
				[[ ! -a $(readlink $FILE) ]] && return 1
				[[ $(readlink $FILE) != $LINK ]] && return 1
			}
			return 0
		}
		[[ $BACKUP == 1 ]] && {
			backup_file -p $FILE
			[[ $? != 0 ]] && return 1
			make_file -l $LINK $FILE
			return $?
		}
		return 1
	}

	log "Invalid TYPE: $TYPE"
	return 1
}

backup_file "${@:1}"
