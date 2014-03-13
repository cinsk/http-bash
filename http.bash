#!/bin/bash

unset $(compgen -v | grep -v -E '^PATH$|^SHELL$|^TERM$|^IFS$|^DIRSTACK$|^HOST|^IFS$|^PPID$|^DOCUMENT_ROOT$') 2>/dev/null

root=${DOCUMENT_ROOT:-~/public_html}
export DOCUMENT_ROOT=`readlink -e $root`

TIMEOUT=20

LOG_LEVEL=5

# CGI output
CGI_OUTFILE=/tmp/http.out.$$
CGI_INFILE=/tmp/http.in.$$
CGI_TIMEOUT=10

export QUERY_STRING=""

log() {
    local lev="$1"
    shift
    [ "$lev" -le "$LOG_LEVEL" ] && printf "%*s" $(((lev - 1) * 2)) " " 1>&2 && echo "$@" 1>&2
}

urlencode() {
    # Usage: urlencode DATA
    # The encoded value is stored in RETVAL.
    RETVAL=$(echo -n "$@" | sed -e 's/%\([0-9A-F][0-9A-F]\)/\\\\\x\1/g' | xargs echo -ne)
}

urldecode() {
    # Usage: urldecode DATA
    # The decoded value is stored in RETVAL.
    local VAR="$@"
    printf -v RETVAL "%b" "${VAR//\%/\x}"
}

set-status-line() {
    # Usage: RESPONSE-CODE MESSAGE
    RESPONSE="HTTP/1.1 $1 $2\r\n"
}

send-status-line() {
    # Usage: send-status-line FIN
    # If additional arg, FIN exists, this function will print additional "\r\n"
    # to mark the end of response.
    echo -ne "$RESPONSE"
    [ "$#" -ne 0 ] && echo -ne "\r\n"
    log 2 "status line: $RESPONSE"
}

is-cgi() {
    # Usage: is-cgi FILENAME
    # return zero if FILENAME ends with ".cgi"
    [[ "$1" =~ \.cgi$ ]] && [ -x "$1" ] && return 0
    return 1
}

url2file() {
    # Usage: URL
    # This function will set RETVAL for the filename, and QUERY_STRING for the query string.
    local arg file

    arg="$1"

    #REQUEST_URI="$arg"

    if [ "$arg" = "/" ]; then
        arg=""
    fi

    if [[ "$arg" =~ ^([^?]*)(\?([^?]*))?$ ]]; then 
        #QUERY_STRING="${BASH_REMATCH[3]}"
        #echo "query: |$QUERY_STRING|" 1>&2
        #export SCRIPT_FILENAME="${BASH_REMATCH[1]}"

        file="$DOCUMENT_ROOT${BASH_REMATCH[1]}"
    else
        file="$DOCUMENT_ROOT$arg"
    fi

    #echo "file: $file" 1>&2

    if [ -d "$file" ]; then
        file="$file/index.html"
    fi

    RETVAL="$file"
    QUERY_STRING="${BASH_REMATCH[3]}"

    log 2 "document: $file"
    log 3 "query string: |$QUERY_STRING|"
}

header-pair() {
    # Usage: header HEADER-LINE
    #
    # parse header line into key and value. The key and the value are
    # stored in RETVAL, and RETVAL2.

    if [[ "$1" =~ ^([^:]+):\ *([^$'\r\n']*)$'\r'?$'\n'?$ ]]; then
        RETVAL="${BASH_REMATCH[1]}"
        RETVAL2="${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

send-headers() {
    # Send all headers, and finishes the response with CRLF.
    for hk in "${!HEADERS[@]}"; do
        echo -ne "$hk: ${HEADERS[$hk]}\r\n"
    done
    echo -ne "\r\n"
}

fill-headers() {
    # Usage: fill-headers FILENAME
    # Fill common response headers into HEADERS variables

    local size date mime="application/octet-stream"

    [[ $(file -i "$1") =~ :\ *([^\ \;]+.*)$ ]] && mime="${BASH_REMATCH[1]}"
    echo "MIME: $mime" 1>&2

    HEADERS[Content-Type]="$mime"
    # TODO: what if stat(1) failed in below command?
    read size date < <(stat -c '%s %Y' "$filename")
    HEADERS[Content-Length]=$size
    HEADERS[Last-Modified]=$(date -R -d @$date)
    #HEADERS[Content-Length]=$(stat -c %s "$filename")
    #HEADERS[Last-Modified]=$(date -R -d @$(stat -c %Y "$filename"))
}

export GATEWAY_INTERFACE="CGI/1.1"
export HOME="$HOME"
export HTTP_HOST SCRIPT_FILENAME CONTENT_TYPE

set-cgi-env() {
    # Usage: set-cgi-env CGI-FILENAME
    HTTP_HOST="${HEADERS[Host]}"
    [ -z "$HTTP_HOST" ] && HTTP_HOST=$(hostname)
    SCRIPT_FILENAME=$(readlink -f "$1")
    CONTENT_TYPE="${HEADERS[Content-Type]}"
}

exec-cgi() {
    # Usage: exec-cgi CGI-FILENAME OUTPUT [INPUT]

    #trap 'rm -f "$CGI_OUTFILE" "$CGI_INFILE"; exit 1' EXIT
    if [ -z "$3" ]; then
        read -t "$CGI_TIMEOUT" < <("$1" >"$2")
    else
        read -t "$CGI_TIMEOUT" < <("$1" <"$3" >"$2")
    fi

    [ $? -gt 128 ] && return 1;	# Failed due to the timeout
    return 0;
}

http-get() {
    if ! is-cgi "$1"; then
        if [ -f "$1" ]; then
            if [ -r "$1" ]; then
                fill-headers "$1"
                send-status-line
                send-headers

                cat "$1"
            else                # File exists, but unreadable
                set-status-line 403 "Forbidden"
                send-status-line EOR
            fi
        else                    # File not found
            set-status-line 404 "Not Found"
            send-status-line EOR
        fi
    else                        # CGI script
        if [ -x "$1" ]; then
            set-cgi-env

            trap 'rm -f "$CGI_OUTFILE"; exit 1' EXIT
            
            if ! exec-cgi "$1" "$CGI_OUTFILE"; then
                set-status-line 500 "Internal Server Error"
                send-status-line EOR
            else
                set-status-line 200 "OK"
                send-status-line
#                send-headers
                cat "$CGI_OUTFILE"
            fi
            rm -f "$CGI_OUTFILE"
            trap '' EXIT
            
            exit 0;             # TODO: Is this needed?
        else
            set-status-line 500 "Internal Server Error"
            send-status-line EOR
        fi
    fi
}

http-head() {
    if [ -f "$1" ]; then
        if [ -r "$1" ]; then
            fill-headers "$1"
            send-status-line
            send-headers

            cat "$1"
        else                # File exists, but unreadable
            set-status-line 403 "Forbidden"
            send-status-line EOR
        fi
    else                    # File not found
        set-status-line 404 "Not Found"
        send-status-line EOR
    fi
}

http-post() {
    local retval

    if [ -z "${HEADERS[Content-Length]}" ]; then
        set-status-line 411 "Length Required"
        send-status-line EOR
        exit 0;
    fi

    trap 'rm -f "$CGI_INFILE" "$CGI_OUTFILE"; exit 1' EXIT
    exec 6<&0
    dd count=1 bs="${HEADERS[Content-Length]}" of="$CGI_INFILE" 2>/dev/null
    exec 0<&6 6<&-
    retval=$?

    [ "$LOG_LEVEL" -ge 3 ] && send-headers 1>&2

    if [ "$LOG_LEVEL" -ge 4 ]; then
        echo "==[BEGINNING OF STDIN]==" 1>&2
        cat "$CGI_INFILE" 1>&2
        echo -e "\n==[END OF STDIN]==" 1>&2 
    fi
        
    if [ "$retval" -ne 0 ]; then
        set-status-line 500 "Internal Server Error (code: $retval)"
        send-status-line EOR
        rm -f "$CGI_INFILE" "$CGI_OUTFILE"
        trap '' EXIT
        exit 0;
    fi

    if ! is-cgi "$1"; then
        if [ -f "$1" ]; then
            set-status-line 405 "Method Not Allowed"
            send-status-line EOR
        else                    # File not found
            set-status-line 404 "Not Found"
            send-status-line EOR
        fi
    else                        # CGI script
        if [ -x "$1" ]; then
            set-cgi-env

            if exec-cgi "$1" "$CGI_OUTFILE" "$CGI_INFILE"; then
                set-status-line 200 "OK"
                send-status-line
                cat "$CGI_OUTFILE"
            else
                set-status-line 500 "Internal Server Error"
                send-status-line EOR
            fi
            rm -f "$CGI_INFILE" "$CGI_OUTFILE"
            trap '' EXIT

            #exit 0;             # TODO: Is this needed?
        else
            set-status-line 500 "Internal Server Error"
            send-status-line EOR
        fi
    fi
    rm -f "$CGI_INFILE" "$CGI_OUTFILE"
    trap '' EXIT
    exit 0
}

declare -A METHOD_DISP
METHOD_DISP[GET]=http-get
METHOD_DISP[HEAD]=http-head
METHOD_DISP[POST]=http-post

declare -A HEADERS
declare -a RESPONSE

export QUERY_STRING

while true; do
    HEADERS=()
    IFS=$'\r\n \t' read -t "$TIMEOUT" method url protocol
    if [ 0 -ne $? ]; then
        exit 0
    fi
    log 1 "$protocol [$method] $url" 1>&2

    RESPONSE=""

    case "$method" in
        HEAD)
            set-status-line 200 "OK"
            ;;
        GET)
            set-status-line 200 "OK"
            #HEADERS[debug]="method($method) url($url) protocol($protocol)"
            ;;
        POST)
            set-status-line 200 "OK"
            ;;
        PUT)
            set-status-line 501 "Method Not Implemented"
            send-status-line EOR
            continue
            ;;
        DELETE)
            set-status-line 501 "Method Not Implemented"
            send-status-line EOR
            continue
            ;;
        *)
            set-status-line 501 "Method Not Implemented"
            send-status-line EOR
            continue
            ;;
    esac
    export REQUEST_METHOD="$method"

    eof=1
    while IFS=$'\r\n' read -t "$TIMEOUT" hdr; do
        if [ -z "$hdr" ]; then
            eof=0
            break
        fi
        header-pair "$hdr" && HEADERS[$RETVAL]="$RETVAL2"
    done
    [ "$eof" -ne 0 ] && exit 1  # disconnected prematurely

    #filename=$(url2file "$url")
    url2file "$url"             # Set RETVAL to filename, and QUERY_STRING
    filename=$RETVAL


    handler="${METHOD_DISP[$REQUEST_METHOD]}"
    echo "handler: $handler" 1>&2
    "$handler" "$filename"
        
done

