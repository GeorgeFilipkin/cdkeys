#!/bin/bash
# option cycle dirstack in visiting order with no regard to current working dir
# option to fill history from .history (what about relatives like cd /etc; cd ./ssh?)
#   can keep pwd_history in a separate file and cycle it like a true history
# cdkeys.zsh cdkeys.bash

# so basically enter starts new side cycle and saves pwd or new down cycle. that's it
# starts with 1 to skip current dir, but keep the dir in cycle

#declare _ck_include_hidden=false
declare -i _ck_down_index=1 
declare -i _ck_side_index=1
declare _ck_next=true  # whether to start new cycle or keep cycling this one
declare _ck_prev=''

_ck_pushd() {
    #echo 'pushd'
    printf -v q "%q" "$1"
    #echo "|$q|"
    if [[ ! " ${DIRSTACK[@]:1} " =~ " ${q} " ]]; then
        pushd -n "$q" &>/dev/null
    fi
}

_ck_pushd "$PWD"

_ck_reorder() {
    #echo "order $1"
    printf -v q "%q" "$1"
    for ((i=1; i<${#DIRSTACK[@]}; i++)); do
        #echo -n "${DIRSTACK[$i]} == $q "
        #[[ "${DIRSTACK[$i]}" == "$q" ]] && echo 'true' || echo 'false'
        if [[ "${DIRSTACK[$i]}" == "$q" ]]; then
            #echo "popd $q at $i"
            popd +$i &>/dev/null
            pushd -n "$q" &>/dev/null
            return
        fi
    done
    return 1
}


cd() {
    #[[ $_ck_next = true ]] && _ck_pushd "$PWD"  # save only next pwd && up
    [[ $_ck_next = true ]] && { _ck_reorder "$PWD" || _ck_pushd "$PWD"; } # save only next pwd && up
    #_ck_pushd "$PWD"  # save any pwd && up
    builtin cd "$@" && { _ck_reorder "$PWD" || _ck_pushd "$PWD"; }
    #builtin cd "$@" && _ck_pushd "$PWD" && _ck_reorder "$PWD" 
    _ck_down_index=1
    _ck_side_index=1
}


_ck_down() {
    _ck_side_index=1
    _ck_old_IFS="$IFS"
    IFS=$'\n'
    if [[ $_ck_next = true || $_ck_prev != 'down' ]]; then
        #echo 'next'
        printf -v _ck_pwd %q "$PWD"
        _ck_next=false
    fi

    _ck_data=($(dirs -p -l | tail +2))
    [[ "${#_ck_data[@]}" -eq 1 ]] && return

    #echo "|${_ck_data[@]}|"

    if [[ "$1" == 'SKIP' ]]; then
        for i in "${_ck_data[@]:$_ck_down_index}"; do
            ((_ck_down_index++))
            #echo "    |$i|$_ck_pwd | $_ck_down_index | $_ck_next"
            #if [[ "$i" == "$_ck_pwd"* ]]; then 
            if [[ "$i" == "$_ck_pwd/"* ]]; then 
                #echo 'found'
                eval "builtin cd $i"
                break
            fi
        done
    else
        # TODO otion to belo
        # cycle in visiting order
        # this just cycles all in stack with no regard to current working dir
        #eval "builtin cd $(printf %q ${_ck_data[$_ck_down_index]})"
        eval "builtin cd ${_ck_data[$_ck_down_index]}"
        ((_ck_down_index++))
    fi

    [[ $_ck_down_index -eq "${#_ck_data[@]}" ]] && _ck_down_index=0
    IFS="$_ck_old_IFS"
    _ck_prev='down'
}


_ck_side() {
    _ck_down_index=1
    _ck_old_IFS="$IFS"
    IFS=$'\n'

    if [[ $_ck_next = true || $_ck_prev == 'down' ]]; then
        if [[ $cdkeys_include_hidden = true ]]; then
            _ck_data=('./' $( -d -1 ./*/ ./.*/ 2> /dev/null | tail +3))
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

    #printf -v t "cd $_ck_pwd/%q" "${_ck_data[$_ck_side_index]}"
    #eval $t
    #echo "$t"
    #builtin cd "$_ck_pwd/$t"
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
