#!/bin/sh
#---------------------------------------------
#   xdg-open
#
#   Utility script to open a URL in the registered default application.
#
#   Refer to the usage() function below for usage.
#
#   Copyright 2009-2010, Fathi Boudra <fabo@freedesktop.org>
#   Copyright 2009-2016, Rex Dieter <rdieter@fedoraproject.org>
#   Copyright 2006, Kevin Krammer <kevin.krammer@gmx.at>
#   Copyright 2006, Jeremy White <jwhite@codeweavers.com>
#
#   LICENSE:
#
#---------------------------------------------

manualpage()
{
cat << _MANUALPAGE
_MANUALPAGE
}

usage()
{
cat << _USAGE
_USAGE
}

#@xdg-utils-common@

# This handles backslashes but not quote marks.
last_word()
{
    read first rest
    echo "$rest"
}

# Get the value of a key in a desktop file's Desktop Entry group.
# Example: Use get_key foo.desktop Exec
# to get the values of the Exec= key for the Desktop Entry group.
get_key()
{
    local file="${1}"
    local key="${2}"
    local desktop_entry=""

    IFS_="${IFS}"
    IFS=""
    while read line
    do
        case "$line" in
            "[Desktop Entry]")
                desktop_entry="y"
            ;;
            # Reset match flag for other groups
            "["*)
                desktop_entry=""
            ;;
            "${key}="*)
                # Only match Desktop Entry group
                if [ -n "${desktop_entry}" ]
                then
                    echo "${line}" | cut -d= -f 2-
                fi
        esac
    done < "${file}"
    IFS="${IFS_}"
}

# Returns true if argument is a file:// URL or path
is_file_url_or_path()
{
    if echo "$1" | grep -q '^file://' \
            || ! echo "$1" | egrep -q '^[[:alpha:]][[:alpha:][:digit:]+\.\-]*:'; then
        return 0
    else
        return 1
    fi
}

# If argument is a file URL, convert it to a (percent-decoded) path.
# If not, leave it as it is.
file_url_to_path()
{
    local file="$1"
    if echo "$file" | grep -q '^file://\(localhost\)\?/'; then
        file=${file#file://localhost}
        file=${file#file://}
        file=${file%%#*}
        file=$(echo "$file" | sed -r 's/\?.*$//')
        local printf=printf
        if [ -x /usr/bin/printf ]; then
            printf=/usr/bin/printf
        fi
        file=$($printf "$(echo "$file" | sed -e 's@%\([a-f0-9A-F]\{2\}\)@\\x\1@g')")
    fi
    echo "$file"
}

open_cygwin()
{
    cygstart "$1"

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_darwin()
{
    open "$1"

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_kde()
{
    if [ -n "${KDE_SESSION_VERSION}" ]; then
      case "${KDE_SESSION_VERSION}" in
        4)
          kde-open "$1"
        ;;
        5)
          kde-open${KDE_SESSION_VERSION} "$1"
        ;;
      esac
    else
        kfmclient exec "$1"
        kfmclient_fix_exit_code $?
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_deepin()
{
    if dde-open -version >/dev/null 2>&1; then
        dde-open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_gnome3()
{
    if gio help open 2>/dev/null 1>&2; then
        gio open "$1"
    elif gvfs-open --help 2>/dev/null 1>&2; then
        gvfs-open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_gnome()
{
    if gio help open 2>/dev/null 1>&2; then
        gio open "$1"
    elif gvfs-open --help 2>/dev/null 1>&2; then
        gvfs-open "$1"
    elif gnome-open --help 2>/dev/null 1>&2; then
        gnome-open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_mate()
{
    if gio help open 2>/dev/null 1>&2; then
        gio open "$1"
    elif gvfs-open --help 2>/dev/null 1>&2; then
        gvfs-open "$1"
    elif mate-open --help 2>/dev/null 1>&2; then
        mate-open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_xfce()
{
    if exo-open --help 2>/dev/null 1>&2; then
        exo-open "$1"
    elif gio help open 2>/dev/null 1>&2; then
        gio open "$1"
    elif gvfs-open --help 2>/dev/null 1>&2; then
        gvfs-open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_enlightenment()
{
    if enlightenment_open --help 2>/dev/null 1>&2; then
        enlightenment_open "$1"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_flatpak()
{
    gdbus call --session \
        --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop \
        --method org.freedesktop.portal.OpenURI.OpenURI \
        "" "$1" {}

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

#-----------------------------------------
# Recursively search .desktop file

search_desktop_file()
{
    local default="$1"
    local dir="$2"
    local target="$3"

    local file=""
    # look for both vendor-app.desktop, vendor/app.desktop
    if [ -r "$dir/$default" ]; then
      file="$dir/$default"
    elif [ -r "$dir/`echo $default | sed -e 's|-|/|'`" ]; then
      file="$dir/`echo $default | sed -e 's|-|/|'`"
    fi

    if [ -r "$file" ] ; then
        command="$(get_key "${file}" "Exec" | first_word)"
        command_exec=`which $command 2>/dev/null`
        icon="$(get_key "${file}" "Icon")"
        # FIXME: Actually LC_MESSAGES should be used as described in
        # http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html
        localised_name="$(get_key "${file}" "Name")"
        set -- $(get_key "${file}" "Exec" | last_word)
        # We need to replace any occurrence of "%f", "%F" and
        # the like by the target file. We examine each
        # argument and append the modified argument to the
        # end then shift.
        local args=$#
        local replaced=0
        while [ $args -gt 0 ]; do
            case $1 in
                %[c])
                    replaced=1
                    arg="${localised_name}"
                    shift
                    set -- "$@" "$arg"
                    ;;
                %[fFuU])
                    replaced=1
                    arg="$target"
                    shift
                    set -- "$@" "$arg"
                    ;;
                %[i])
                    replaced=1
                    shift
                    set -- "$@" "--icon" "$icon"
                    ;;
                *)
                    arg="$1"
                    shift
                    set -- "$@" "$arg"
                    ;;
            esac
            args=$(( $args - 1 ))
        done
        [ $replaced -eq 1 ] || set -- "$@" "$target"
        "$command_exec" "$@"

        if [ $? -eq 0 ]; then
            exit_success
        fi
    fi

    for d in $dir/*/; do
        [ -d "$d" ] && search_desktop_file "$default" "$d" "$target"
    done
}


open_generic_xdg_mime()
{
    filetype="$2"
    default=`xdg-mime query default "$filetype"`
    if [ -n "$default" ] ; then
        xdg_user_dir="$XDG_DATA_HOME"
        [ -n "$xdg_user_dir" ] || xdg_user_dir="$HOME/.local/share"

        xdg_system_dirs="$XDG_DATA_DIRS"
        [ -n "$xdg_system_dirs" ] || xdg_system_dirs=/usr/local/share/:/usr/share/

DEBUG 3 "$xdg_user_dir:$xdg_system_dirs"
        for x in `echo "$xdg_user_dir:$xdg_system_dirs" | sed 's/:/ /g'`; do
            search_desktop_file "$default" "$x/applications/" "$1"
        done
    fi
}

open_generic_xdg_file_mime()
{
    filetype=`xdg-mime query filetype "$1" | sed "s/;.*//"`
    open_generic_xdg_mime "$1" "$filetype"
}

open_generic_xdg_x_scheme_handler()
{
    scheme="`echo $1 | sed -n 's/\(^[[:alnum:]+\.-]*\):.*$/\1/p'`"
    if [ -n $scheme ]; then
        filetype="x-scheme-handler/$scheme"
        open_generic_xdg_mime "$1" "$filetype"
    fi
}

has_single_argument()
{
  test $# = 1
}

open_envvar()
{
    local oldifs="$IFS"
    local browser browser_with_arg

    IFS=":"
    for browser in $BROWSER; do
        IFS="$oldifs"

        if [ -z "$browser" ]; then
            continue
        fi

        if echo "$browser" | grep -q %s; then
            # Avoid argument injection.
            # See https://bugs.freedesktop.org/show_bug.cgi?id=103807
            # URIs don't have IFS characters spaces anyway.
            has_single_argument $1 && $(printf "$browser" "$1")
        else
            $browser "$1"
        fi

        if [ $? -eq 0 ]; then
            exit_success
        fi
    done
}

open_generic()
{
    if is_file_url_or_path "$1"; then
        local file="$(file_url_to_path "$1")"

        check_input_file "$file"

        if has_display; then
            filetype=`xdg-mime query filetype "$file" | sed "s/;.*//"`
            open_generic_xdg_mime "$file" "$filetype"
        fi

        if which run-mailcap 2>/dev/null 1>&2; then
            run-mailcap --action=view "$file"
            if [ $? -eq 0 ]; then
                exit_success
            fi
        fi

        if has_display && mimeopen -v 2>/dev/null 1>&2; then
            mimeopen -L -n "$file"
            if [ $? -eq 0 ]; then
                exit_success
            fi
        fi
    fi

    if has_display; then
        open_generic_xdg_x_scheme_handler "$1"
    fi

    if [ -n "$BROWSER" ]; then
        open_envvar "$1"
    fi

    # if BROWSER variable is not set, check some well known browsers instead
    if [ x"$BROWSER" = x"" ]; then
        BROWSER=www-browser:links2:elinks:links:lynx:w3m
        if has_display; then
            BROWSER=x-www-browser:firefox:iceweasel:seamonkey:mozilla:epiphany:konqueror:chromium:chromium-browser:google-chrome:$BROWSER
        fi
    fi

    open_envvar "$1"

    exit_failure_operation_impossible "no method available for opening '$1'"
}

open_lxde()
{

    # pcmanfm only knows how to handle file:// urls and filepaths, it seems.
    if pcmanfm --help >/dev/null 2>&1 && is_file_url_or_path "$1"; then
        local file="$(file_url_to_path "$1")"

        # handle relative paths
        if ! echo "$file" | grep -q ^/; then
            file="$(pwd)/$file"
        fi

        pcmanfm "$file"
    else
        open_generic "$1"
    fi

    if [ $? -eq 0 ]; then
        exit_success
    else
        exit_failure_operation_failed
    fi
}

open_lxqt()
{
    open_generic "$1"
}

[ x"$1" != x"" ] || exit_failure_syntax

url=
while [ $# -gt 0 ] ; do
    parm="$1"
    shift

    case "$parm" in
      -*)
        exit_failure_syntax "unexpected option '$parm'"
        ;;

      *)
        if [ -n "$url" ] ; then
            exit_failure_syntax "unexpected argument '$parm'"
        fi
        url="$parm"
        ;;
    esac
done

if [ -z "${url}" ] ; then
    exit_failure_syntax "file or URL argument missing"
fi

detectDE

if [ x"$DE" = x"" ]; then
    DE=generic
fi

DEBUG 2 "Selected DE $DE"

# sanitize BROWSER (avoid calling ourselves in particular)
case "${BROWSER}" in
    *:"xdg-open"|"xdg-open":*)
        BROWSER=$(echo $BROWSER | sed -e 's|:xdg-open||g' -e 's|xdg-open:||g')
        ;;
    "xdg-open")
        BROWSER=
        ;;
esac

case "$DE" in
    kde)
    open_kde "$url"
    ;;

    deepin)
    open_deepin "$url"
    ;;

    gnome3|cinnamon)
    open_gnome3 "$url"
    ;;

    gnome)
    open_gnome "$url"
    ;;

    mate)
    open_mate "$url"
    ;;

    xfce)
    open_xfce "$url"
    ;;

    lxde)
    open_lxde "$url"
    ;;

    lxqt)
    open_lxqt "$url"
    ;;

    enlightenment)
    open_enlightenment "$url"
    ;;

    cygwin)
    open_cygwin "$url"
    ;;

    darwin)
    open_darwin "$url"
    ;;

    flatpak)
    open_flatpak "$url"
    ;;

    generic)
    open_generic "$url"
    ;;

    *)
    exit_failure_operation_impossible "no method available for opening '$url'"
    ;;
esac