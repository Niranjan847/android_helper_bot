#!/usr/bin/env bash

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Create input & working directory if it does not exist
mkdir -p $PROJECT_DIR/input $PROJECT_DIR/working

# GitHub token
if [[ -n $2 ]]; then
    GIT_OAUTH_TOKEN=$2
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(cat .githubtoken)
else
    echo "Please provide github oauth token as a parameter or place it in a file called .githubtoken in the root of this repo"
    exit 1
fi

# download or copy from local?
URL=$1

cd $PROJECT_DIR/input
echo "Downloading file"
aria2c -q -s 16 -x 16 ${URL:?} || wget ${URL:?} || exit 1 #download rom
echo "Done"

ORG=AndroidDumps #for orgs support, here can write your org name
IFS='?' read -r -a array <<< "$URL"
if [[ ${URL} == *"googleusercontent"* ]];then
    REGEX_FL='(?<=filename=").*?(?=";)'
    output=`wget -q -O - --server-response --spider $URL 2>&1`
    FILE=`echo $output | grep -Po $REGEX_FL`
    EXTENSION=${FILE##*.}
else
    URL=${array[0]}
    FILE=${URL##*/}
    EXTENSION=${URL##*.}
fi

UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system vendor cust odm oem factory product modem xrom systemex"

$PROJECT_DIR/Firmware_extractor/extractor.sh $PROJECT_DIR/input/${FILE} $PROJECT_DIR/working/${UNZIP_DIR}

cd $PROJECT_DIR/working/${UNZIP_DIR}

if [ ! -d "$PROJECT_DIR/extract-dtb" ]; then
    git clone https://github.com/PabloCastellano/extract-dtb $PROJECT_DIR/extract-dtb
fi
python3 $PROJECT_DIR/extract-dtb/extract-dtb.py $PROJECT_DIR/working/${UNZIP_DIR}/boot.img -o $PROJECT_DIR/working/${UNZIP_DIR}/bootimg > /dev/null # Extract boot

if [[ -f $PROJECT_DIR/working/${UNZIP_DIR}/dtbo.img ]]; then
    python3 $PROJECT_DIR/extract-dtb/extract-dtb.py $PROJECT_DIR/working/${UNZIP_DIR}/dtbo.img -o $PROJECT_DIR/working/${UNZIP_DIR}/dtbo > /dev/null # Extract dtbo
fi

# Extract dts
mkdir $PROJECT_DIR/working/${UNZIP_DIR}/bootdts
dtb_list=`find $PROJECT_DIR/working/${UNZIP_DIR}/bootimg -name '*.dtb' -type f -printf '%P\n' | sort`
for dtb_file in $dtb_list; do
	dtc -I dtb -O dts -o $(echo "$PROJECT_DIR/working/${UNZIP_DIR}/bootdts/$dtb_file" | sed -r 's|.dtb|.dts|g') $PROJECT_DIR/working/${UNZIP_DIR}/bootimg/$dtb_file > /dev/null 2>&1
done

for p in $PARTITIONS; do
    if [ -e "$PROJECT_DIR/working/${UNZIP_DIR}/$p.img" ]; then
        mkdir $p || rm -rf $p/*
        7z x $p.img -y -o$p/ 2>/dev/null >> zip.log
        rm $p.img 2>/dev/null
    fi
done
rm zip.log

echo "All partitions extracted"

# board-info.txt
find $PROJECT_DIR/working/${UNZIP_DIR}/modem -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
find $PROJECT_DIR/working/${UNZIP_DIR}/tz* -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
if [ -e $PROJECT_DIR/working/${UNZIP_DIR}/vendor/build.prop ]; then
	strings $PROJECT_DIR/working/${UNZIP_DIR}/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt
fi
sort -u -o $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt $PROJECT_DIR/working/${UNZIP_DIR}/board-info.txt

#copy file names
sudo chown $(whoami) * -R ; chmod -R u+rwX * #ensure final permissions
find $PROJECT_DIR/working/${UNZIP_DIR} -type f -printf '%P\n' | sort | grep -v ".git/" > $PROJECT_DIR/working/${UNZIP_DIR}/all_files.txt

ls system/build*.prop 2>/dev/null || ls system/system/build*.prop 2>/dev/null || { echo "No system build*.prop found, pushing cancelled!" && exit ;}

flavor=$(grep -oP "(?<=^ro.build.flavor=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.vendor.build.flavor=).*" -hs vendor/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.system.build.flavor=).*" -hs {system,system/system}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.build.type=).*" -hs {system,system/system}/build*.prop)
release=$(grep -oP "(?<=^ro.build.version.release=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.vendor.build.version.release=).*" -hs vendor/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.system.build.version.release=).*" -hs {system,system/system}/build*.prop)
id=$(grep -oP "(?<=^ro.build.id=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.vendor.build.id=).*" -hs vendor/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.system.build.id=).*" -hs {system,system/system}/build*.prop)
incremental=$(grep -oP "(?<=^ro.build.version.incremental=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.vendor.build.version.incremental=).*" -hs vendor/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.system.build.version.incremental=).*" -hs {system,system/system}/build*.prop)
tags=$(grep -oP "(?<=^ro.build.tags=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.vendor.build.tags=).*" -hs vendor/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.system.build.tags=).*" -hs {system,system/system}/build*.prop)
fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.vendor.build.fingerprint=).*" -hs vendor/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.system.build.fingerprint=).*" -hs {system,system/system}/build*.prop)
brand=$(grep -oP "(?<=^ro.product.brand=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.vendor.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.vendor.product.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(echo $fingerprint | cut -d / -f1 )
codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.vendor.product.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(echo $fingerprint | cut -d / -f3 | cut -d : -f1 )
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.build.fota.version=).*" -hs {system,system/system}/build*.prop | cut -d - -f1 | head -1)
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build*.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
branch=$(echo $description | tr ' ' '-')
repo=$(echo $brand\_$codename\_dump | tr '[:upper:]' '[:lower:]')

printf "\nbrand: $brand - codename: $codename - branch: $branch - repo: $repo\n"

echo "Init git repo"
output=`git init`
#if [ -z "$(git config --get user.email)" ]; then
    git config user.email AndroidDumps@github.com
#fi
#if [ -z "$(git config --get user.name)" ]; then
    git config user.name AndroidDumps
#fi
output=`git checkout -b $branch`
find -size +97M -printf '%P\n' -o -name *sensetime* -printf '%P\n' -o -name *.lic -printf '%P\n' > .gitignore
output=`git add --all`

echo "Creating github repo if needed"
output=`curl -s -X POST -H "Authorization: token ${GIT_OAUTH_TOKEN}" -d '{ "name": "'"$repo"'" }' "https://api.github.com/orgs/${ORG}/repos"` #create new repo
output=`git remote add origin https://github.com/$ORG/${repo,,}.git`
#echo $output
output=`git commit -asm "Add ${description}"`
#echo $output
echo "Pushing files"
output=`git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ||

(git update-ref -d HEAD ; git reset system/ vendor/ ;
git checkout -b $branch ;
git commit -asm "Add extras for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add vendor/ ;
git commit -asm "Add vendor for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add system/system/app/ system/system/priv-app/ || git add system/app/ system/priv-app/ ;
git commit -asm "Add apps for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add system/ ;
git commit -asm "Add system for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;)`
#echo $output
echo "Done"


exit 0
