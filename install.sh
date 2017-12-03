#!/bin/bash
DOTFILESINSTALL=true
BASEDIR=$(dirname $0)
QUIET=0
VERBOSE=0
INIT=0

backlogs=()
function backlog () {
	backlogs+=("${@}")
}

backvlogs=()
function backvlog () {
	backvlogs+=("${@}")
}

function logbacklogs () {
	[[ $INIT == 0 ]] && return 1
	for l in "${backlogs[@]}" ; do
		log "${l}"
	done
	for l in "${backvlogs[@]}" ; do
		vlog "${l}"
	done
}

function log () {
	[[ $INIT == 0 ]] && backlog "${@}" && return
	[[ $QUIET == 1 ]] && [[ $VERBOSE == 0 ]] && return
	echo "${@}" >&2
}

function vlog () {
	[[ $INIT == 0 ]] && backvlog "${@}" && return
	[[ $VERBOSE == 0 ]] && return
	echo "${@}" >&2
}

function main () {
	usage="usage: $(basename "$0") [-h] [-p] [-e] <path>

	DootInstaller v0.1.0
	(c) 2017 Maddison Hellstrom
	https://github.com/b0o/dootfiles
	MIT License

	It installs your doots, what else do you expect from me?

	Options:
		 -h          Display this message and exit.
		 -q          Run in quiet mode
		 -V          Run in verbose mode - overrides quiet mode
		 -c          Specify the configuration file - defaults to ./dootrc
		 -i          Specify the install directory.
		             Overrides INSTALLDIR from dootrc
		 -s          Specify the source directory.
		             Overrides SOURCEDIR from dootrc
		 -b          Specify the bin directory.
		             Overrides BINDIR from dootrc
		 -v          Specify the vendor directory.
		             Overrides VENDORDIR from dootrc
		 -r          Specify a vendor repository URL.
		             Can be specified multiple times for multiple repos
		             Appended to VENDORREPOS from dootrc
		 -R          Specify all vendor repository URLs, comma delimited
		             Overrides VENDORREPOS from dootrc and -r options

		--- TODO ---
		 -d          Specify a single dootfile to install from within SOURCEDIR
		             Can be specified multiple times for multiple dootfiles
		             If specified, only these dootfiles will be installed
		             If not specified, all dootfiles within SOURCEDIR will be installed
		 -Y          Bypass any and all confirmation messages, selecting the safest
		             option by default.
		 -D          Dry run
	"
	# Default option values
	DOOTRC="$BASEDIR/dootrc"
	OPT_INSTALLDIR=""
	OPT_SOURCEDIR=""
	OPT_BINDIR=""
	OPT_VENDORDIR=""
	OPT_VENDORREPOS=()
	OPT_VENDORREPOS_R=()
	vlog "Parsing options:"
	while getopts 'hqVc:i:s:b:v:r:R:' option; do
		case "$option" in
			h) echo "$usage"
				exit 1
				;;
			q) QUIET=1;                          vlog "-q (QUIET) set to '${QUIET}'"
				;;
			V) VERBOSE=1;                        vlog "-v (VERBOSE) set to '${VERBOSE}'"
				;;
			c) DOOTRC="${OPTARG}";               vlog "-c (DOOTRC) set to '${DOOTRC}'"
				;;
			i) OPT_INSTALLDIR="${OPTARG}";       vlog "-i (OPT_INSTALLDIR) set to '${OPT_INSTALLDIR}'"
				;;
			s) OPT_SOURCEDIR="${OPTARG}";        vlog "-s (OPT_SOURCEDIR) set to '${OPT_SOURCEDIR}'"
				;;
			b) OPT_BINDIR="${OPTARG}";           vlog "-b (OPT_BINDIR) set to '${OPT_BINDIR}'"
				;;
			v) OPT_VENDORDIR="${OPTARG}";        vlog "-v (OPT_VENDORDIR) set to '${OPT_VENDORDIR}'"
				;;
			r) OPT_VENDORREPOS+=("${OPTARG}");   vlog "-r (OPT_VENDORREPOS) set to '${OPT_VENDORREPOS[@]}'"
				;;
			R) # https://stackoverflow.com/a/45201229/8202881
				readarray -td '' a < <(awk '{ gsub(/,/,"\0"); print; }' <<< "$OPTARG, "); unset 'a[-1]';
				OPT_VENDORREPOS_R=(${a[@]});       vlog "-R (OPT_VENDORREPOS_R) set to '${OPT_VENDORREPOS[@]}'"
				;;
			\?) logf "Error: illegal option: -%s\n" "${OPTARG}"
				log "$usage"
				exit 1
				;;
		esac
	done
	shift $(($OPTIND - 1))

	# log messages from before verbose/quiet variables could be set
	INIT=1
	logbacklogs

	# Validate $DOOTRC before sourcing it
	DOOTRC="$(realpath $DOOTRC)"
	[[ ! -f $DOOTRC ]] && {
		log "Error: Configuration file $DOOTRC not found"
		exit 1
	}
	[[ ! -r $DOOTRC ]] && {
		log "Error: Unable to read configuration file $DOOTRC"
		exit 1
	}

	vlog "Sourcing $DOOTRC..."
	source $DOOTRC

	[[ ! -z $OPT_INSTALLDIR ]]      && INSTALLDIR=$OPT_INSTALLDIR
	[[ ! -z $OPT_SOURCEDIR ]]       && SOURCEDIR=$OPT_SOURCEDIR
	[[ ! -z $OPT_BINDIR ]]          && BINDIR=$OPT_BINDIR
	[[ ! -z $OPT_VENDORDIR ]]       && VENDORDIR=$OPT_VENDORDIR
	[[ ${#OPT_VENDORREPOS} > 0 ]]   && VENDORREPOS+=(${OPT_VENDORREPOS[@]})
	[[ ${#OPT_VENDORREPOS_R} > 0 ]] && VENDORREPOS=(${OPT_VENDORREPOS_R[@]})

	vlog "Using these settings:"
	vlog "INSTALLDIR:  $INSTALLDIR"
	vlog "SOURCEDIR:   $SOURCEDIR"
	vlog "BINDIR:      $BINDIR"
	vlog "VENDORDIR:   $VENDORDIR"
	vlog "VENDORREPOS: ${VENDORREPOS[@]}"
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
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to copy $FILE to $BAKPATH"
			return $c
		}
		vlog "Removing original file $FILE after backing up to $BAKPATH"
		rm -rf $FILE
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to remove $FILE after backing up"
			return $c
		}
		return 0
	}

	# Overwrite
	[[ $response =~ ^([bB])$ ]] && {
		log "Overwriting $FILE"
		rm -rf $FILE
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to overwrite $FILE"
			return $c
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
	usage="usage: $(basename "$0"):${FUNCNAME[0]} [-h] [-d|f|l <source>] <path>

	Attempt create a new file, directory, or symlink

	Options:
		 -h          Display this message and exit.
		 -r          If the parent directory of the specified file does not exist, attempt to create it (recursive)
		 -d          Attempt to create a directory
		 -f          Attempt to create a normal file (default)
		 -l <source> Attempt to create a symlink pointing to <source>
	"
	TYPE="f"
	LINK=""
	RECURSIVE=0
	while getopts 'hrdfl:' option; do
		case "$option" in
			h) log "$usage"
				exit 1
				;;
			r) RECURSIVE=1;   vlog "-r (RECURSIVE) set to '${RECURSIVE}'"
				;;
			d) TYPE="d";      vlog "-d (TYPE) set to '${TYPE}'"
				;;
			f) TYPE="f";      vlog "-f (TYPE) set to '${TYPE}'"
				;;
			l) TYPE="l";      vlog "-l (TYPE) set to '${TYPE}'"
				LINK="$OPTARG"; vlog "-l (LINK) set to '${LINK}'"
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

	[[ -a $FILE ]] && {
		log "Error: $FILE already exists"
		return 1
	}

	FILENAME="$(basename "$FILE")"
	FILEDIR="$(dirname "$FILE")"

	[[ -a $FILEDIR ]] && {
		[[ -d $FILEDIR ]] && {
			[[ ! -w $FILEDIR ]] && {
				log "Error: $DIR is not writable"
				return 1
			}
		} || {
			log "Error: $DIR exists but is not a directory"
			return 1
		}
	} || {
		[[ $RECURSIVE == 1 ]] && {
			make_file -d -r $FILEDIR
			c=$?
			[[ $c != 0 ]] && {
				log "Error: Unable to create directory $FILEDIR"
				return $c
			}
		} || {
			log "Error: $DIR does not exist (specify -r to create it)"
			return 1
		}
	}

	[[ $TYPE == 'd' ]] && {
		mkdir $FILE
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to create directory $FILE"
			return $c
		}
		return 0
	}

	[[ $TYPE == 'f' ]] && {
		touch $FILE
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to create file $FILE"
			return $c
		}
		return 0
	}

	[[ $TYPE == 'l' ]] && {
		ln -s $LINK $FILE
		c=$?
		[[ $c != 0 ]] && {
			log "Error: Unable to create symlink $FILE -> $LINK"
			return $c
		}
		return 0
	}

	log "Invalid TYPE: $TYPE"
	return 1
}

function ensure_exists () {
	usage="usage: $(basename "$0"):${FUNCNAME[0]} [-h] [-m] [-p] [-w] [-d|f|l <source>] <path>

	Ensure a file exists at the given path

	Options:
		 -h          Display this message and exit.
		 -m          Create the file if it doesn't exist
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
			arg="-${TYPE}"
			[[ $TYPE == 'l' ]] && {
				[[ $ENSURELINK == 1 ]] && {
					[[ ! -a $LINK ]] && return 1
				}
				arg="${arg} $LINK"
			}
			make_file $arg $FILE
			c=$?
			[[ $c != 0 ]] && {
				log "Error: Unable to make_file $FILE"
				return $c
			} || {
				return 0
			}
		}
		return 1
	}

	[[ $TYPE == 'd' ]] && {
		[[ -d $FILE ]] && {
			return 0
		} || {
			[[ $BACKUP == 1 ]] && {
				backup_file -p $FILE
				c=$?
				[[ $c != 0 ]] && {
					log "Error: Unable to backup_file $FILE"
					return $c
				}
				make_file -d $FILE
				c=$?
				[[ $c != 0 ]] && {
					log "Error: Unable to make_file $FILE"
					return $c
				}
				return 0
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
				c=$?
				[[ $c != 0 ]] && {
					log "Error: Unable to backup_file $FILE"
					return $c
				}
				make_file -f $FILE
				c=$?
				[[ $c != 0 ]] && {
					log "Error: Unable to make_file $FILE"
					return $c
				}
				return 0
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
			c=$?
			[[ $c != 0 ]] && {
				log "Error: Unable to backup_file $FILE"
				return $c
			}
			make_file -l $LINK $FILE
			c=$?
			[[ $c != 0 ]] && {
				log "Error: Unable to make_file $FILE"
				return $c
			}
			return 0
		}
		return 1
	}

	log "Invalid TYPE: $TYPE"
	return 1
}

main "${@}"
