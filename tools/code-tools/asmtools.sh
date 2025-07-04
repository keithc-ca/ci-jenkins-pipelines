#!/bin/bash

###################################################################
# Script to build asmtools to be reused by jdk testing community  #
# currently builds tip of master and tip of at8 branch            #
# In future, it should clone and build:                           #
# tip of master, latest release in master, and tip of at7 branch  #
###################################################################

# shellcheck disable=SC2035,SC2155
set -euo pipefail
WORKSPACE=$PWD

function generateArtifact() {
    local  branchOrTag=${1}
    export JAVA_HOME=${2}
    local testLog=test.log
    git checkout $branchOrTag
    echo "Moving into maven build..."
    pushd maven
      echo "Removing asmtools $branchOrTag old maven wrapper"
      rm -rf src target pom.xml $testLog
      #export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF8 -Xdoclint:none -Dmaven.javadoc.skip=true -Dgpg.skip"
      echo "Generating asmtools $branchOrTag maven wrapper"
      sh mvngen.sh
      echo "Cleaning possible previous run"
      mvn clean
      pushd ../..
        tar --exclude='**asmtools*.jar' \
            --exclude='**asmtools*.tar.gz' \
            --exclude='**asmtools*.txt' \
            --exclude='**asmtools*.jar.html' \
            --exclude='**asmtools*.jar.md' \
            --exclude='**src.tar.gz' \
        -czf src.tar.gz asmtools
      popd
      echo "Running asmtools $branchOrTag tests by $JAVA_HOME"
      mvn test 2>&1 | tee $testLog || echo "Test now correctly fails, this have to be fixed upstream"
      echo "Running asmtools $branchOrTag build by $JAVA_HOME"
      mvn package -DskipTests # mvn install will do much more, but I doubt we wish that (javadoc, sources, gpg sign...)
      echo "Moving down to target"
      pushd target
        echo "Asmtools $branchOrTag artifact:"
        ls -l
        local mainArtifact=$(ls asmtools*.jar)
        echo "Copying maven/target/$mainArtifact file to RESULTS_DIR($RESULTS_DIR)"
        cp  $mainArtifact $RESULTS_DIR
        if [ -e surefire-reports ] ; then
          local testResults=$(echo $mainArtifact | sed "s/.jar/-tests.tar.gz/")
          echo "Compressing and archiving test results as $testResults"
          tar -czf $testResults surefire-reports
          echo "Copying maven/target/$testResults file to RESULTS_DIR($RESULTS_DIR)"
          cp  $testResults $RESULTS_DIR
          pushd ..
            echo "Moving maven/$testLog file to RESULTS_DIR($RESULTS_DIR)"
            mv $testLog $RESULTS_DIR/$mainArtifact.tests.txt
          popd
        else
          echo "No test results!"
        fi
        pushd ../..
          echo "Copying README files and src archive to RESULTS_DIR($RESULTS_DIR)"
          cp -v README.html $RESULTS_DIR/$mainArtifact.html
          cp -v README.md $RESULTS_DIR/$mainArtifact.md
          mv -v ../src.tar.gz $RESULTS_DIR/$mainArtifact.src.tar.gz
        popd
      popd
    popd
}

function renameLegacyCoreArtifacts() {
  echo "copying 'core' maven names to legacy ant names"
  for file in $(ls asmtools*.jar asmtools*-tests.tar.gz) ; do
      if echo $file | grep -q -e core ; then
      local nwFile=$(echo $file | sed "s/-core//")
      ln -fv $file $nwFile
      fi
  done
}

function hashArtifacts() {
  echo "Creating checksums all asmtools*.jar"
  for file in $(ls asmtools*.jar asmtools*-tests.tar.gz) ; do
      sha256sum $file > $file.sha256sum.txt
  done
}

function detectJdks() {
  jvm_dir="/usr/lib/jvm/"
  find ${jvm_dir} -maxdepth 1 | sort
  echo "Available jdks 8 in ${jvm_dir}:"
  find ${jvm_dir} -maxdepth 1 | sort | grep -e java-1.8.0-  -e jdk-8
  echo "Available jdks 17 in ${jvm_dir}:"
  find ${jvm_dir} -maxdepth 1 | sort | grep -e java-17-     -e jdk-17
  echo "Available jdks 21 in ${jvm_dir}:"
  find ${jvm_dir} -maxdepth 1 | sort | grep -e java-21-     -e jdk-21
  jdk08=$(readlink -f $(find ${jvm_dir} -maxdepth 1 | sort | grep -e java-1.8.0-  -e jdk-8   | head -n 1))
  jdk17=$(readlink -f $(find ${jvm_dir} -maxdepth 1 | sort | grep -e java-17-     -e jdk-17  | head -n 1))
  jdk21=$(readlink -f $(find ${jvm_dir} -maxdepth 1 | sort | grep -e java-21-     -e jdk-21  | head -n 1))
}

function getProperty() {
  local file=build/productinfo.properties
  cat $file | grep ^$1 | sed "s/.*=\s*//g"
}

function getVersion() {
  local PRODUCT_VERSION=$(getProperty PRODUCT_VERSION)
  local PRODUCT_MILESTONE=$(getProperty PRODUCT_MILESTONE)
  local PRODUCT_BUILDNUMBER=$(getProperty PRODUCT_BUILDNUMBER)
  if [ "x$PRODUCT_MILESTONE" == x ] ; then
    PRODUCT_MILESTONE="ga"
  fi
  echo $PRODUCT_VERSION.b$PRODUCT_BUILDNUMBER-$PRODUCT_MILESTONE
}
	
REPO_DIR="asmtools"
if [ ! -e $REPO_DIR ] ; then
  git clone https://github.com/openjdk/$REPO_DIR.git
fi
detectJdks
pushd $REPO_DIR
  RESULTS_DIR="$(pwd)"
  latestRelease=$(git tag -l | tail -n 2 | head -n 1)
  generateArtifact "master" "$jdk21"
  masterVersion=$(getVersion)
  generateArtifact "8.0-b09" "$jdk17"
  at8Version=$(getVersion)
  generateArtifact "at7" "$jdk08"
  at7Version=$(getVersion)
  renameLegacyCoreArtifacts
  releaseCandidate7=asmtools-core-$at7Version.jar
  releaseName7=asmtools07.jar
  releaseCandidate8=asmtools-$at8Version.jar
  releaseName8=asmtools08.jar
  releaseCandidate=asmtools-$masterVersion.jar
  releaseName=asmtools.jar
  echo "Manually renaming  $releaseCandidate7 as $releaseName7 to provide latest-7-stable-recommended file"
  ln -fv $releaseCandidate7 $releaseName7
  echo "Manually renaming  $releaseCandidate8 as $releaseName8 to provide latest-8-stable-recommended file"
  ln -fv $releaseCandidate8 $releaseName8
  echo "Manually renaming  $releaseCandidate as $releaseName to provide latest-stable-recommended file"
  ln -fv $releaseCandidate $releaseName
  hashArtifacts
  echo "Resetting repo back to master"
  git checkout master
popd
