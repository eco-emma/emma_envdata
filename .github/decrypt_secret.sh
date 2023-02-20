#!/bin/sh

# Decrypt the file

mkdir -p $HOME/.config/earthengine/ndef/

mkdir -p /home/rstudio/.config/earthengine/ndef/

mkdir -p /github/home/config/earthengine

# --batch to prevent interactive command
# --yes to assume "yes" for questions


# Decrypt ee credentials (currently decrypting to a bunch of places hoping that earth engine finds one)

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output $HOME/.config/earthengine/ndef/credentials ./scratch_code/credentials.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output /home/rstudio/.config/earthengine/ndef/credentials ./scratch_code/credentials.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output ~/.config/earthengine/credentials ./scratch_code/credentials.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output /github/home/config/earthengine/credentials ./scratch_code/credentials.gpg


# Decrypt google drive credentials
gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output $HOME/.config/earthengine/ndef/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com ./scratch_code/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output /home/rstudio/.config/earthengine/ndef/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com ./scratch_code/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com.gpg


# Decrypt google drive credentials (newer version)

#Note: directly encrypting hte .json provided by Google failed.  Instead, I loaded it into R, re-saved it, THEN encrypted the new version.

echo " re-saved json 1 "
gpg --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output ./scratch_code/maitner_creds2.json ./scratch_code/maitner_creds2.json.gpg
