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

echo " gd1 "

gpg --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output /home/rstudio/.config/earthengine/ndef/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg

echo " gd2 "

gpg --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output $HOME/.config/earthengine/ndef/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg

echo " gd3 "

gpg --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output ./scratch_code/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg



# Decrypt test

echo " test 1 "
gpg --batch --yes --decrypt --passphrase="$TEST" \
--output ./scratch_code/output.json ./scratch_code/output.json.gpg

echo " test 2 "

gpg --batch --yes --decrypt --passphrase="test" \
--output ./scratch_code/output2.json ./scratch_code/output.json.gpg
