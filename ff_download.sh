#!/bin/bash
# ╭──────────────────────────────────────────────────────────────────────────────╮
# │                                                                              │
# │              Download a video or file to use in the scriptflow               │
# │                                                                              │
# ╰──────────────────────────────────────────────────────────────────────────────╯

# ╭──────────────────────────────────────────────────────────╮
# │                       Set Defaults                       │
# ╰──────────────────────────────────────────────────────────╯

# set -o errexit                                              # If a command fails bash exits.
# set -o pipefail                                             # pipeline fails on one command.
if [[ "${DEBUG-0}" == "1" ]]; then set -o xtrace; fi        # DEBUG=1 will show debugging.


# ╭──────────────────────────────────────────────────────────╮
# │                        VARIABLES                         │
# ╰──────────────────────────────────────────────────────────╯
INPUT_URL=""
OUTPUT_FILENAME="ff_download.mp4"
STRATEGY="1"
LOGLEVEL="error" 
TMP_FILE="/tmp/tmp_ff_download_list"
FILELIST="./filelist.txt"

# ╭──────────────────────────────────────────────────────────╮
# │                          Usage.                          │
# ╰──────────────────────────────────────────────────────────╯

usage()
{
    if [ "$#" -lt 2 ]; then
        printf "ℹ️ Usage:\n $0 -i <INPUT_URL> [-s <STRATEGY>] [-o <OUTPUT_FILE>] [-l loglevel]\n\n" >&2 

        printf "Summary:\n"
        printf "Change the FPS of a video without changing the length..\n\n"

        printf "Flags:\n"

        printf " -i | --input <INPUT_URL>\n"
        printf "\tThe input url to download.\n\n"

        printf " -o | --output <OUTPUT_FILE>\n"
        printf "\tDefault is %s\n" "${OUTPUT_FILENAME}"
        printf "\tThe name of the output file.\n\n"

        printf " -u | --urlsource <FILE_WITH_LIST>\n"
        printf "\tA URL of a txt file with a list of all files to use as inputs. Separated one per line.\n\n"

        printf " -s | --strategy <STRATEGY>\n"
        printf "\t5\t A number. First 5 videos from inputs. Prefix number on output filename. Default 1.\n"
        printf "\t~5\t Tilde(~) followed by a number. Random 5 videos from inputs. Prefix number on output filename.\n\n"

        printf " -C | --config <CONFIG_FILE>\n"
        printf "\tSupply a config.json file with settings instead of command-line. Requires JQ installed.\n\n"

        printf " -l | --loglevel <LOGLEVEL>\n"
        printf "\tThe FFMPEG loglevel to use. Default is 'error' only.\n"
        printf "\tOptions: quiet,panic,fatal,error,warning,info,verbose,debug,trace\n"

        exit 1
    fi
}


# ╭──────────────────────────────────────────────────────────╮
# │         Take the arguments from the command line         │
# ╰──────────────────────────────────────────────────────────╯
function arguments()
{
    POSITIONAL_ARGS=()

    while [[ $# -gt 0 ]]; do
    case $1 in


        -i|--input|--input?|--input??|--input???)
            write_to_temp "$2"
            shift
            shift
            ;;


        -u|--urlsource)
            URL_SOURCE="$2"
            shift
            shift
            ;;


        -o|--output)
            OUTPUT_FILENAME="$2"
            shift 
            shift
            ;;


        -s|--strategy)
            STRATEGY="$2"
            shift 
            shift
            ;;


        -l|--loglevel)
            LOGLEVEL="$2"
            shift 
            shift
            ;;


        -C|--config)
            CONFIG_FILE="$2"
            shift 
            shift
            ;;


        --description)              # IGNORED. used for descriptions in JSON 
            shift
            shift
            ;;


        -*|--*)
            echo "Unknown option $1"
            exit 1
            ;;


        *)
            POSITIONAL_ARGS+=("$1") # save positional arg back onto variable
            shift                   # remove argument and shift past it.
            ;;
    esac
    done

}



# ╭──────────────────────────────────────────────────────────╮
# │        Read config-file if supplied. Requires JQ         │
# ╰──────────────────────────────────────────────────────────╯
function read_config()
{
    # Check if config has been set.
    if [ -z ${CONFIG_FILE+x} ]; then return 0; fi
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        printf "JQ is a dependency and could not be found. Please install JQ for JSON parsing. Exiting.\n"
        exit
    fi

    # Read file
    LIST_OF_INPUTS=$(cat ${CONFIG_FILE} | jq -r 'to_entries[] | ["--" + .key, .value] | @sh' | xargs) 

    # Print to screen
    printf "🎛️  Config Flags: %s\n" "$LIST_OF_INPUTS"

    # Send to the arguments function again to override.
    arguments $LIST_OF_INPUTS
}


# ╭───────────────────────────────────────────────────────────────────────────╮
# │         Reads the URL txt file and creates --inputs for each line         │
# ╰───────────────────────────────────────────────────────────────────────────╯
function read_url_input_list()
{
    # Check if a url source has been set.
    if [ -z ${URL_SOURCE+x} ]; then return 0; fi

    # download txt file
    curl --insecure --silent --show-error --url "$URL_SOURCE" --output ${FILELIST} 2>/dev/null

    # Check if file exists.
    if [ ! -f ${FILELIST} ]; then return 0; fi

    # Get the directory URL 
    DIR_NAME=$(dirname ${URL_SOURCE})

    # append INPUTS to the LIST_OF_INPUTS
    while read LINE; do
        LIST_OF_INPUTS="${LIST_OF_INPUTS} --input ${DIR_NAME}/${LINE}"
    done < ${FILELIST}

    # Send to the arguments function again to override.
    arguments $LIST_OF_INPUTS
}



# ╭──────────────────────────────────────────────────────────╮
# │     Write the absolute path into the temporary file      │
# ╰──────────────────────────────────────────────────────────╯
function write_to_temp()
{
    FILE=$1
    # print line into temp file.
    printf "%s\n" "${FILE}" >> ${TMP_FILE}
}



# ╭──────────────────────────────────────────────────────────╮
# │   Exit the app by just skipping the ffmpeg processing.   │
# │            Then copy the input to the output.            │
# ╰──────────────────────────────────────────────────────────╯
function exit_gracefully()
{
    cp -f ${INPUT_FILENAME} ${OUTPUT_FILENAME}
    exit 0
}



function configure_strategy()
{
    INPUT_FILE=$1

    # If its a number, take top X
    REGEX='^[0-9]+$'
    if [[ "${STRATEGY}" =~ $REGEX ]] ; then
        cat ${TMP_FILE} | head -n ${STRATEGY} > ${TMP_FILE}.random
        printf "\nignore sort error - by design.\n"
        mv ${TMP_FILE}.random ${TMP_FILE}
    fi


    # If its a tilde ~ followed by a number, randomise and take top X
    REGEX='^~[0-9]+$'
    if [[ "${STRATEGY}" =~ $REGEX ]] ; then
        cat ${TMP_FILE} | sort -R | head -n ${STRATEGY:1} > ${TMP_FILE}.random
        printf "\nignore sort error - by design.\n"
        mv ${TMP_FILE}.random ${TMP_FILE}
    fi
}


# ╭──────────────────────────────────────────────────────────╮
# │                         Cleanup                          │
# ╰──────────────────────────────────────────────────────────╯
function cleanup()
{
    rm -f ${TMP_FILE}
    rm -f ${FILELIST}
}



# ╭──────────────────────────────────────────────────────────╮
# │                                                          │
# │                      Main Function                       │
# │                                                          │
# ╰──────────────────────────────────────────────────────────╯
function main()
{

    printf "%-80s\n" "⬇️  ff_download.sh - Download a video/file for usage in scriptflow."

    configure_strategy
    
    LOOP=1
    while read FILE; do

        # Filename
        OUTPUT_FILE=${LOOP}_${OUTPUT_FILENAME}

        # printf
        printf "\nDownloading: %s to %s " "$FILE" "$OUTPUT_FILE"

        # download
        curl --insecure --silent --show-error --url "$FILE" --output ${OUTPUT_FILE} 2>/dev/null

        # Iterate.
        LOOP=$(( $LOOP + 1 ))

    done < ${TMP_FILE}
    
    printf "\n✅ %-20s\n" "${OUTPUT_FILENAME}"

}

cleanup
usage $@
arguments $@
read_config "$@"
read_url_input_list "$@"
main $@
cleanup