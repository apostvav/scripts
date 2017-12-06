#!/bin/bash
# Generate Certificate Server Request

domains=( "$@" )
passphrase=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 32 | head -n 1)
certsdir="$HOME/certificates"
datetime=$(date +"%Y%m%d%H%M%S")
passwordless=1;

usage(){
    echo "Usage: ${0} example.com www.example.com ftp.example.com";
}

if [[ "$#" -lt 1 ]]; then
    echo "You should pass at least one fqdn."
    usage
    exit 1
fi

if [[ "$@" == "--help" || "$@" == "-h" ]]; then
    usage
    exit 0
fi

# Validate domains
for domain in "${domains[@]}"
do
    check_domain=`echo $domain | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'`
    if [[ -z $check_domain ]]; then
        echo "$domain is not a FQDN!"
        exit 1
    fi
done

# Create Certifications Directory
certsdir="$certsdir/${1}-$datetime"
if [ ! -d "$certsdir" ]; then
    mkdir -p "$certsdir"
fi

# Create a password protected key
echo "$passphrase" | openssl genrsa -des3 -out "$certsdir/${1}.secured.key" -passout stdin 2048

# Request Configuration
cnf_template="[ req ]
default_bits            = 2048
distinguished_name      = usr
prompt                  = no
req_extensions          = v3_req

[ usr ]
C = Country
L = State
O = Me, Inc.
OU = Me, Dpt.
CN = ${1}

[ v3_req ]
subjectAltName = DNS:${1}"

# Append Subject Alt Names to Configuration
if [[ "$#" -gt 1 ]]; then
    for ((i=1; i<${#}; i++))
    do
        cnf_template="$cnf_template, DNS:${domains[$i]}"
    done
fi

# Save Configuration to file
echo -e "${cnf_template}" > "$certsdir/${1}.cnf"


# Generate CSR
if [[ $passwordless -ne 0 ]]; then
    # Generate CSR using a passwordless key
    echo "$passphrase" | openssl rsa -in "$certsdir/${1}.secured.key" -out "$certsdir/${1}.key" -passin stdin
    rm "$certsdir/${1}.secured.key"
    privkey="${1}.key"
    openssl req -new -key "$certsdir/$privkey" -config "$certsdir/${1}.cnf" -out "$certsdir/${1}.csr" -sha256
else
    # Generate CSR with a password protected key
    echo "Secret key is: $passphrase"
    privkey="${1}.secured.key"
    echo $passphrase | openssl req -new -key "$certsdir/$privkey" -config "$certsdir/${1}.cnf" -out "$certsdir/${1}.csr" -sha256 -passin stdin
fi

echo "Files stored into $certsdir directory."
