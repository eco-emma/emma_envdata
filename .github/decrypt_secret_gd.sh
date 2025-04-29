#!/bin/sh

# Decrypt the file


# --batch to prevent interactive command
# --yes to assume "yes" for questions


# Decrypt google drive credentials (newer version)
gpg --quiet --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output /home/rstudio/.config/earthengine/ndef/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output $HOME/.config/earthengine/ndef/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg

gpg --quiet --batch --yes --decrypt --passphrase="$GD_SECRET" \
--output $HOME/.config/earthengine/ndef/maitner-f590bfc7be54.json ./scratch_code/maitner-f590bfc7be54.json.gpg

