#!/bin/bash

#declare cdkeys_include_hidden=false

# starts with 1 to skip current dir, but keep the dir in cycle
declare -i _ck_down_index=1 
declare -i _ck_side_index=1

declare -i _ck_hs_index=0
declare -a _CK_HSSTACK
declare -i _ck_hsstack_start_length=0

declare _ck_next=true  # whether to start new side/down cycle or keep cycling this one
declare _ck_prev=''


_ck_load_hs () {
    _CK_HSSTACK=($(cat ~/.cdkeys_history | uniq))
    _ck_hsstack_start_length="${#_CK_HSSTACK[@]}"
} && _ck_load_hs


_ck_pushh() {
    printf -v q "%q" "$1"
    if [[ ${#_CK_HSSTACK[@]} -eq 0 || "${_CK_HSSTACK[-1]}" != "$q" ]]; then
        _CK_HSSTACK+=("$q")
    fi
}


_ck_pushd() {
    printf -v q "%q" "$1"
    if [[ ! " ${DIRSTACK[@]:1} " =~ " ${q} " ]]; then
        pushd -n "$q" &>/dev/null
    fi
} && _ck_pushd "$PWD"


_ck_reorder() {
    printf -v q "%q" "$1"
    for ((i=1; i<${#DIRSTACK[@]}; i++)); do
        if [[ "${DIRSTACK[$i]}" == "$q" ]]; then
            popd +$i &>/dev/null
            pushd -n "$q" &>/dev/null
            return
        fi
    done
    return 1
}


cd() {
    [[ $_ck_next = true ]] && { _ck_reorder "$PWD" || _ck_pushd "$PWD"; } # save before cd
    builtin cd "$@" && { _ck_reorder "$PWD" || _ck_pushd "$PWD"; } && _ck_pushh "$PWD" # save any pwd after cd
    _ck_down_index=1
    _ck_side_index=1
}


_ck_down() {
    _ck_hs_index=0
    _ck_side_index=1
    _ck_old_IFS="$IFS"
    IFS=$'\n'
    if [[ $_ck_next = true || $_ck_prev != 'down' ]]; then
        printf -v _ck_pwd %q "$PWD"
        _ck_next=false
    fi

    _ck_data=($(dirs -p -l | tail +2))
    [[ "${#_ck_data[@]}" -eq 1 ]] && return

    for i in "${_ck_data[@]:$_ck_down_index}"; do
        ((_ck_down_index++))
        if [[ "$i" == "$_ck_pwd/"* ]]; then
            eval "builtin cd $i"
            break
        fi
    done

    [[ $_ck_down_index -eq "${#_ck_data[@]}" ]] && _ck_down_index=0
    IFS="$_ck_old_IFS"
    _ck_prev='down'
}


_ck_save_hs() {
    # TODO on exit should also check for _ck_next and if it's true write it down
    [[ "${#_CK_HSSTACK[@]}" -le $_ck_hsstack_start_length ]] && return # no new paths to write
    printf '%s\n' "${_CK_HSSTACK[@]:$_ck_hsstack_start_length}" | uniq >> ~/.cdkeys_history
}
trap _ck_save_hs SIGINT SIGTERM SIGQUIT SIGKILL EXIT


_ck_hs() {
    _ck_down_index=1
    _ck_side_index=1
    _ck_old_IFS="$IFS"
    IFS=$'\n'

    echo "$_ck_next"

    [[ "$1" == 'backward' ]] && ((_ck_hs_index-=1)) || ((_ck_hs_index+=1))
    eval "builtin cd ${_CK_HSSTACK[$_ck_hs_index]}"

    if [[ ${_ck_hs_index#-} -eq "${#_CK_HSSTACK[@]}" ]]; then
        echo 'reset'
        _ck_hs_index=0
    fi
    IFS="$_ck_old_IFS"
    _ck_prev='hs'
}


_ck_side() {
    _ck_hs_index=0
    _ck_down_index=1
    _ck_old_IFS="$IFS"
    IFS=$'\n'

    if [[ $_ck_next = true || $_ck_prev == 'down' ]]; then
        if [[ $cdkeys_include_hidden = true ]]; then
            _ck_data=('./' $(ls -d -1 ./*/ ./.*/ 2> /dev/null | tail +3))
        else
            _ck_data=('./' $(ls -d -1 ./*/ 2> /dev/null))
        fi
        printf -v _ck_pwd %q "$PWD"
        _ck_next=false
        _ck_side_index=1
        unset _ck_prev
        [[ ! "${#_ck_data[@]}" -eq 1 ]] && cd "$PWD" # save current
    fi

    [[ "${#_ck_data[@]}" -eq 1 ]] && return

    if [[ "$1" == 'left' ]]; then
        [[ $_ck_prev == 'right' ]] && ((_ck_side_index--))
        ((_ck_side_index--))
        _ck_prev='left'
    fi

    [[ "$1" == 'right' && $_ck_prev == 'left' ]] && ((_ck_side_index++))

    eval "builtin cd $_ck_pwd/$(printf %q ${_ck_data[$_ck_side_index]})"

    if [[ "$1" == 'right' ]]; then
        ((_ck_side_index++))
        _ck_prev='right'
    fi

    [[ ${_ck_side_index#-} -ge ${#_ck_data[@]} ]] && _ck_side_index=0
    IFS="$_ck_old_IFS"
}


#### PREBINDS

# next
bind -x '"\C-__next":"_ck_next=true"'
bind '"\C-__j"':accept-line
bind '"\C-j":"\C-__next\C-__j"'
bind '"\C-M":"\C-__next\C-__j"'

# up
# (this can also execute readline_line in the dir above: ll M^ (should probably fix it))
bind -x '"\C-__up":"cd .."'
bind '"\C-_up": "\C-__up\C-j"'

# down
bind -x '"\C-__down"':"_ck_down"
bind '"\C-_down": "\C-__down\C-__j"'

# hs
bind -x '"\C-__forward"':"_ck_hs forward"
bind '"\C-_forward": "\C-__forward\C-__j"'
bind -x '"\C-__backward"':"_ck_hs backward"
bind '"\C-_backward": "\C-__backward\C-__j"'

# side
bind -x '"\C-__left"':"_ck_side left"
bind '"\C-_left": "\C-__left\C-__j"'
bind -x '"\C-__right"':"_ck_side right"
bind '"\C-_right": "\C-__right\C-__j"'


#### BINDS

bind '"\e[1;3A": "\C-_up"'
bind '"\e[1;3B": "\C-_down"'
bind '"\e[1;3D": "\C-_left"'
bind '"\e[1;3C": "\C-_right"'

bind '"\C-n": "\C-_forward"'
bind '"\C-p": "\C-_backward"'
