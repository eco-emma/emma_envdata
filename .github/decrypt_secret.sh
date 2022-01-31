#!/bin/sh

# Decrypt the file

mkdir -p $HOME/.config/earthengine/ndef/

# --batch to prevent interactive command
# --yes to assume "yes" for questions

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output $HOME/.config/earthengine/ndef/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com ./scratch_code/20061abcbc1c6ecf51bd9cf7e37350f6_bmaitner@gmail.com.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$RGEE_SECRET" \
--output $HOME/.config/earthengine/ndef/credentials $HOME/emma_envdata/scratch_code/credentials.gpg
