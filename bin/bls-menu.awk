# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Aleph1-9012
# Adapted from Sidonia's Fedora BLS reader.
# Convert Fedora type-1 BLS records to the equivalent native GRUB commands.
# Input is data: no shell command or BLS value is executed while generating.
function quote(s,    r,i,c) {
    r="'"
    for(i=1;i<=length(s);i++) {c=substr(s,i,1); r=r (c=="'" ? "'\\''" : c)}
    return r "'"
}
function versioncmp(a,b,    x,y,numeric) {
    while(a!="" || b!="") {
        sub(/^[^[:alnum:]~+]+/,"",a); sub(/^[^[:alnum:]~+]+/,"",b)
        x=substr(a,1,1); y=substr(b,1,1)
        if(x=="~" || y=="~") {
            if(x!="~") return 1
            if(y!="~") return -1
            a=substr(a,2); b=substr(b,2); continue
        }
        if(x=="+" || y=="+") {
            if(a=="") return -1
            if(b=="") return 1
            if(x!="+") return 1
            if(y!="+") return -1
            a=substr(a,2); b=substr(b,2); continue
        }
        if(a=="" || b=="") break
        numeric=(a ~ /^[0-9]/)
        if(numeric) {match(a,/^[0-9]+/);x=substr(a,1,RLENGTH);match(b,/^[0-9]*/);y=substr(b,1,RLENGTH)}
        else {match(a,/^[[:alpha:]]+/);x=substr(a,1,RLENGTH);match(b,/^[[:alpha:]]*/);y=substr(b,1,RLENGTH)}
        if(y=="") return (numeric ? 1 : -1)
        a=substr(a,length(x)+1); b=substr(b,length(y)+1)
        if(numeric) {
            sub(/^0+/,"",x); sub(/^0+/,"",y)
            if(length(x)!=length(y)) return (length(x)>length(y) ? 1 : -1)
        }
        if("x" x != "x" y) return ("x" x > "x" y ? 1 : -1)
    }
    return (a!="" ? 1 : (b!="" ? -1 : 0))
}
function compare(a,b,    na,nb,va,vb,ra,rb,r) {
    na=a; nb=b; sub(/-[^-]*$/,"",na); sub(/-[^-]*$/,"",nb)
    ra=substr(a,length(na)+2); rb=substr(b,length(nb)+2)
    va=na; vb=nb; sub(/-[^-]*$/,"",na); sub(/-[^-]*$/,"",nb)
    va=substr(va,length(na)+2); vb=substr(vb,length(nb)+2)
    r=versioncmp(na,nb); if(r) return r
    r=versioncmp(va,vb); if(r) return r
    return versioncmp(ra,rb)
}
function path(s) {return s ~ /^\/[[:alnum:]_+.\/~:-]+$/ && s !~ /(^|\/)\.\.(\/|$)/}
function emit(id,    title,linux,options,j,header,initrd,value,dt) {
    linux=fields[id,"linux",1]
    if(linux=="") {failed=1; return}
    if(!path(linux)) {failed=1; return}
    title=fields[id,"title",1]; if(title=="") title=linux
    if(title ~ /[$\\[:cntrl:]]/) {failed=1;return}
    header="menuentry " quote(title) " --id=" quote(id)
    for(j=1;j<=counts[id,"grub_arg"];j++) {
        value=fields[id,"grub_arg",j]
        if(value!="--unrestricted") {failed=1;return}
    }
    value=fields[id,"grub_users",1]
    if(value=="$grub_users") {
        print "set eva_bls_access=--unrestricted"
        print "if [ -n \"$grub_users\" ]; then set eva_bls_access=\"--users=$grub_users\"; fi"
        header=header " \"$eva_bls_access\""
    } else if(value=="") header=header " --unrestricted"
    else if(value ~ /^[[:alnum:]_,.-]+$/) header=header " --users " quote(value)
    else {failed=1;return}
    for(j=1;j<=counts[id,"grub_class"];j++) header=header " --class " quote(fields[id,"grub_class",j])
    value=fields[id,"grub_hotkey",1]
    if(value!="") header=header " --hotkey " quote(value)
    print header " {"
    print "  set root=\"$eva_bls_root\""
    print "  if [ \"$save_default\" = true ]; then savedefault; fi"
    print "  load_video\n  set gfxpayload=keep\n  insmod gzio"
    options=fields[id,"options",1]
    if(options=="") options="$default_kernelopts"
    if(options ~ /[;{}\r\n`]/ || options ~ /\$[0-9@*?#]/) {failed=1;return}
    print "  linux ($root)" linux " " options
    initrd=""
    for(j=1;j<=counts[id,"initrd"];j++) {
        value=fields[id,"initrd",j]
        if(!path(value)) {failed=1;return}
        initrd=initrd " ($root)" value
    }
    if(initrd!="") print "  initrd" initrd
    dt=fields[id,"devicetree",1]
    if(dt!="") {
        if(!path(dt)) {failed=1;return}
        print "  devicetree ($root)" dt
    }
    print "}"
    entries++
}
FNR==1 {
    id=FILENAME; sub(/^.*\//,"",id); sub(/\.conf$/,"",id)
    if(id !~ /^[[:alnum:]_+.~:-]+$/) {failed=1;exit 2}
    names[++n]=id
}
{
    sub(/\r$/,"",$0)
    if($0 ~ /^[[:space:]]*(#|$)/) next
    key=$1; value=$0; sub(/^[^[:space:]]+[[:space:]]*/,"",value)
    if(key !~ /^(title|version|machine-id|linux|initrd|options|grub_users|grub_arg|grub_class|grub_hotkey|devicetree)$/ || value ~ /[\r\n]/) {failed=1;exit 2}
    if(key !~ /^(initrd|grub_arg|grub_class)$/ && counts[id,key]) {failed=1;exit 2}
    fields[id,key,++counts[id,key]]=value
}
END {
    if(failed) exit 2
    for(i=2;i<=n;i++) {
        id=names[i]; j=i-1
        while(j>0 && compare(id,names[j])>0) {names[j+1]=names[j];j--}
        names[j+1]=id
    }
    print "set eva_bls_root=\"$eva_bls_device\""
    print "export eva_bls_root"
    for(i=1;i<=n;i++) emit(names[i])
    if(failed || !entries) exit 2
}
