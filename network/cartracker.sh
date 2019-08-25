#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will orchestrate a sample end-to-end execution of the Hyperledger
# Fabric network.
#
# The end-to-end verification provisions a sample Fabric network consisting of
# two organizations, each maintaining two peers, and a “solo” ordering service.
#
# This verification makes use of two fundamental tools, which are necessary to
# create a functioning transactional network with digital signature validation
# and access control:
#
# * cryptogen - generates the x509 certificates used to identify and
#   authenticate the various components in the network.
# * configtxgen - generates the requisite configuration artifacts for orderer
#   bootstrap and channel creation.
#
# Each tool consumes a configuration yaml file, within which we specify the topology
# of our network (cryptogen) and the location of our certificates for various
# configuration operations (configtxgen).  Once the tools have been successfully run,
# we are able to launch our network.  More detail on the tools and the structure of
# the network will be provided later in this document.  For now, let's get going...

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired

export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}

# By default we standup a full network.
DEV_MODE=false

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  cartracker.sh up|down|restart|generate|reset|clean|upgrade|createneworg|startneworg|stopneworg [-c <channel name>] [-f <docker-compose-file>] [-i <imagetag>] [-o <logfile>] [-dev]"
  echo "  cartracker.sh -h|--help (print this message)"
  echo "    <mode> - one of 'up', 'down', 'restart' or 'generate'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'restart' - restart the network"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "      - 'reset' - delete chaincode containers while keeping network artifacts"
  echo "      - 'clean' - delete network artifacts"
  echo "      - 'upgrade'  - upgrade the network from v1.0.x to v1.1"
  echo "    -c <channel name> - channel name to use (defaults to \"cartrackerchannel\")"
  echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose-e2e.yaml)"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -d - Apply command to the network in dev mode."
  echo "    -l <orgs> - Specify list of orgs. Ex: -l \"Org1 Org2 Org3\""
  echo "    -p <domain name> - Specify the domain name. Ex: -y example.com"
  echo "    -r <orderer name> - Specify the orderer name. Ex: -r ExampleOrderer"
  echo
  echo "Typically, one would first generate the required certificates and "
  echo "genesis block, then bring up the network. e.g.:"
  echo
  echo "	cartracker.sh generate -c cartrackerchannel"
  echo "	cartracker.sh up -c cartrackerchannel -o logs/network.log"
  echo "        cartracker.sh up -c cartrackerchannel -i 1.1.0-alpha"
  echo "	cartracker.sh down -c cartrackerchannel"
  echo "        cartracker.sh upgrade -c cartrackerchannel"
  echo
  echo "Taking all defaults:"
  echo "	cartracker.sh generate"
  echo "	cartracker.sh up"
  echo "	cartracker.sh down"
}

# Keeps pushd silent
pushd() {
  command pushd "$@" >/dev/null
}

# Keeps popd silent
popd() {
  command popd "$@" >/dev/null
}

# Ask user for confirmation to proceed
function askProceed() {
  read -p "Continue? [Y/n] " ans
  case "$ans" in
  y | Y | "")
    echo "proceeding ..."
    ;;
  n | N)
    echo "exiting..."
    exit 1
    ;;
  *)
    echo "invalid response"
    askProceed
    ;;
  esac
}

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
function clearContainers() {
  CONTAINER_IDS=$(docker ps -aq)
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# TODO list generated image naming patterns
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available.  In the future, additional checking for the presence
# of go or other items could be added.
function checkPrereqs() {
  # Note, we check configtxlator externally because it does not require a config file, and peer in the
  # docker image because of FAB-8551 that makes configtxlator return 'development version' in docker
  LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
    echo -e "You can update to to the latest production release by executing the following command:\ncurl -sSL http://bit.ly/2ysbOFE | bash -s"
    exit 0
  fi

}

# Start the network.
function networkUp() {
  checkPrereqs
  # Create folder for docker network logs
  LOG_DIR=$(dirname $LOG_FILE)
  if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
  fi
  IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE up >$LOG_FILE 2>&1 &
  docker ps
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    exit 1
  fi
}

# Generate the needed certificates, the configuration, and start the network components for the new org.
function newOrgNetworkUp() {
  checkPrereqs
  # generate artifacts if they don't exist
  if [ ! -d "crypto-config/peerOrganizations/exportingentityorg.trade.com" ]; then
    generateCertsForNewOrg
    replacePrivateKeyForNewOrg
    generateChannelConfigForNewOrg
  fi
  # Create folder for docker network logs
  LOG_DIR=$(dirname $LOG_FILE_NEW_ORG)
  if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
  fi
  IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_NEW_ORG up >$LOG_FILE_NEW_ORG 2>&1 &
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    exit 1
  fi
}

# Upgrade the network from one version to another
# If the new image tag (now in the IMAGETAG variable) is not passed in the command line using the "-i" switch:
# 	this assumes that the new iamge has already been tagged with "latest".
# Stop the orderer and peers, backup the ledger from orderer and peers, cleanup chaincode containers and images
# and relaunch the orderer and peers with latest tag
function upgradeNetwork() {
  docker inspect -f '{{.Config.Volumes}}' orderer.trade.com | grep -q '/var/hyperledger/production/orderer'
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! This network does not appear to be using volumes for its ledgers, did you start from fabric-samples >= v1.0.6?"
    exit 1
  fi

  LEDGERS_BACKUP=./ledgers-backup

  # create ledger-backup directory
  mkdir -p $LEDGERS_BACKUP

  export IMAGE_TAG=$IMAGETAG
  COMPOSE_FILES="-f $COMPOSE_FILE"

  echo "Upgrading orderer"
  docker-compose $COMPOSE_FILES stop orderer.trade.com
  docker cp -a orderer.trade.com:/var/hyperledger/production/orderer $LEDGERS_BACKUP/orderer.trade.com
  docker-compose $COMPOSE_FILES up --no-deps orderer.trade.com

  for PEER in peer0.exporterorg.trade.com peer0.dealershiporg.trade.com peer0.carrierorg.trade.com peer0.regulatororg.trade.com; do
    echo "Upgrading peer $PEER"

    # Stop the peer and backup its ledger
    docker-compose $COMPOSE_FILES stop $PEER
    docker cp -a $PEER:/var/hyperledger/production $LEDGERS_BACKUP/$PEER/

    # Remove any old containers and images for this peer
    CC_CONTAINERS=$(docker ps | grep dev-$PEER | awk '{print $1}')
    if [ -n "$CC_CONTAINERS" ]; then
      docker rm -f $CC_CONTAINERS
    fi
    CC_IMAGES=$(docker images | grep dev-$PEER | awk '{print $1}')
    if [ -n "$CC_IMAGES" ]; then
      docker rmi -f $CC_IMAGES
    fi

    # Start the peer again
    docker-compose $COMPOSE_FILES up --no-deps $PEER
  done
}

# Bring down running network
function networkDown() {

  docker-compose -f $COMPOSE_FILE down --volumes

  for PEER in peer0.exporterorg.trade.com peer0.dealershiporg.trade.com peer0.carrierorg.trade.com peer0.regulatororg.trade.com; do
    # Remove any old containers and images for this peer
    CC_CONTAINERS=$(docker ps -a | grep dev-$PEER | awk '{print $1}')
    if [ -n "$CC_CONTAINERS" ]; then
      docker rm -f $CC_CONTAINERS
    fi
  done

}

# Bring down running network components of the new org
function newOrgNetworkDown() {
  docker-compose -f $COMPOSE_FILE_NEW_ORG down --volumes

  for PEER in peer0.exportingentityorg.trade.com; do
    # Remove any old containers and images for this peer
    CC_CONTAINERS=$(docker ps -a | grep dev-$PEER | awk '{print $1}')
    if [ -n "$CC_CONTAINERS" ]; then
      docker rm -f $CC_CONTAINERS
    fi
  done
}

# Delete network artifacts
function networkClean() {
  #Cleanup the chaincode containers
  clearContainers
  #Cleanup images
  removeUnwantedImages
  # remove orderer block and other channel configuration transactions and certs
  rm -rf channel-artifacts crypto-config add_org/crypto-config
  # remove the docker-compose yaml file that was customized to the example
  rm -f docker-compose-e2e.yaml add_org/docker-compose-exportingEntityOrg.yaml
  # remove client certs
  rm -rf client-certs
}

# Using docker-compose-e2e-template.yaml, replace constants with private key file names
# generated by the cryptogen tool and output a docker-compose.yaml specific to this
# configuration
function replacePrivateKey() {
  # Copy the template to the file that will be modified to add the private key
  cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  CURRENT_DIR=$PWD
  for org in $ORGS_LIST; do
    cd crypto-config/peerOrganizations/${org,,}.$DOMAIN_NAME/ca/
    PRIV_KEY=$(ls *_sk)
    cd "$CURRENT_DIR"
    sed -i "s/${org}_CA_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
  done
}

function replacePrivateKeyForNewOrg() {
  # Copy the template to the file that will be modified to add the private key
  cp add_org/docker-compose-exportingEntityOrg-template.yaml add_org/docker-compose-exportingEntityOrg.yaml

  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  CURRENT_DIR=$PWD
  cd crypto-config/peerOrganizations/exportingentityorg.trade.com/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  if [ $(uname -s) == 'Darwin' ]; then
    sed -i '' "s/EXPORTINGENTITY_CA_PRIVATE_KEY/${PRIV_KEY}/g" add_org/docker-compose-exportingEntityOrg.yaml
  else
    sed -i "s/EXPORTINGENTITY_CA_PRIVATE_KEY/${PRIV_KEY}/g" add_org/docker-compose-exportingEntityOrg.yaml
  fi
}

# We will use the cryptogen tool to generate the cryptographic material (x509 certs)
# for our various network entities.  The certificates are based on a standard PKI
# implementation where validation is achieved by reaching a common trust anchor.
#
# Cryptogen consumes a file - ``crypto-config.yaml`` - that contains the network
# topology and allows us to generate a library of certificates for both the
# Organizations and the components that belong to those Organizations.  Each
# Organization is provisioned a unique root certificate (``ca-cert``), that binds
# specific components (peers and orderers) to that Org.  Transactions and communications
# within Fabric are signed by an entity's private key (``keystore``), and then verified
# by means of a public key (``signcerts``).  You will notice a "count" variable within
# this file.  We use this to specify the number of peers per Organization; in our
# case it's two peers per Org.  The rest of this template is extremely
# self-explanatory.
#
# After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

# Generates Org certs using cryptogen tool
function generateCerts() {
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "##########################################################"
  echo "##### Generate certificates using cryptogen tool #########"
  echo "##########################################################"

  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  set -x
  cryptogen generate --config=./crypto-config.yaml
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate certificates..."
    exit 1
  fi
  echo
}

function generateCertsForNewOrg() {
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "######################################################################"
  echo "##### Generate certificates for new org using cryptogen tool #########"
  echo "######################################################################"

  if [ -d "crypto-config/peerOrganizations/exportingentityorg.trade.com" ]; then
    rm -Rf crypto-config/peerOrganizations/exportingentityorg.trade.com
  fi
  set -x
  cryptogen generate --config=./add_org/crypto-config.yaml
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate certificates..."
    exit 1
  fi
  echo
}

# The `configtxgen tool is used to create four artifacts: orderer **bootstrap
# block**, fabric **channel configuration transaction**, and two **anchor
# peer transactions** - one for each Peer Org.
#
# The orderer block is the genesis block for the ordering service, and the
# channel transaction file is broadcast to the orderer at channel creation
# time.  The anchor peer transactions, as the name might suggest, specify each
# Org's anchor peer on this channel.
#
# Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
# for the sample network. There are five members - one Orderer Org (``TradeOrdererOrg``)
# and four Peer Orgs (``ExporterOrg``, ``DealershipOrg``, ``CarrierOrg`` & ``RegulatorOrg``)
# each managing and maintaining one peer node.
# This file also specifies a consortium - ``TradeConsortium`` - consisting of our
# four Peer Orgs.  Pay specific attention to the "Profiles" section at the top of
# this file.  You will notice that we have two unique headers. One for the orderer genesis
# block - ``FourOrgsTradeOrdererGenesis`` - and one for our channel - ``FourOrgscartrackerchannel``.
# These headers are important, as we will pass them in as arguments when we create
# our artifacts.  This file also contains two additional specifications that are worth
# noting.  Firstly, we specify the anchor peers for each Peer Org
# (``peer0.exporterorg.trade.com`` & ``peer0.dealershiporg.trade.com``).  Secondly, we point to
# the location of the MSP directory for each member, in turn allowing us to store the
# root certificates for each Org in the orderer genesis block.  This is a critical
# concept. Now any network entity communicating with the ordering service can have
# its digital signature verified.
#
# This function will generate the crypto material and our four configuration
# artifacts, and subsequently output these files into the ``channel-artifacts``
# folder.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# Generate orderer genesis block, channel configuration transaction and
# anchor peer update transactions
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi

  mkdir -p channel-artifacts

  echo "###########################################################"
  echo "#########  Generating Orderer Genesis block  ##############"
  echo "###########################################################"

  ORDERER_PROFILE=${PROFILE_NAME}OrdererGenesis
  CHANNEL_PROFILE=${PROFILE_NAME}Channel

  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  set -x
  configtxgen -profile $ORDERER_PROFILE -outputBlock ./channel-artifacts/genesis.block -channelID orderer-system-channel
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate orderer genesis block..."
    exit 1
  fi
  echo
  echo "###################################################################"
  echo "###  Generating channel configuration transaction  'channel.tx' ###"
  echo "###################################################################"
  set -x
  configtxgen -profile $CHANNEL_PROFILE -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate channel configuration transaction..."
    exit 1
  fi

  for org in $ORGS_LIST; do
    echo
    echo "#####################################################################"
    echo "#######  Generating anchor peer update for ${org}MSP  ##########"
    echo "#####################################################################"
    set -x
    configtxgen -profile $CHANNEL_PROFILE -outputAnchorPeersUpdate ./channel-artifacts/${org}MSPanchors.tx -channelID $CHANNEL_NAME -asOrg $org
    res=$?
    set +x
    if [ $res -ne 0 ]; then
      echo "Failed to generate anchor peer update for ${org}MSP..."
      exit 1
    fi
  done
  echo "Done generating channel artifacts."
}

# Generate configuration (policies, certificates) for new org in JSON format
function generateChannelConfigForNewOrg() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi

  mkdir -p channel-artifacts

  echo "####################################################################################"
  echo "#########  Generating Channel Configuration for Exporting Entity Org  ##############"
  echo "####################################################################################"
  set -x
  FABRIC_CFG_PATH=${PWD}/add_org/ && configtxgen -printOrg ExportingEntityOrgMSP -channelID $CHANNEL_NAME >./channel-artifacts/exportingEntityOrg.json
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate channel configuration for exportingentity org..."
    exit 1
  fi
  echo
}

function generateDockerComposeFile() {
  echo "generating docker-compose-e2e-template file"
  # Check and delete existing config files
  if [ -f docker-compose-e2e-template.yaml ]; then
    rm -f docker-compose-e2e-template.yaml
  fi
  if [ -f docker-compose-e2e.yaml ]; then
    rm -f docker-compose-e2e.yaml
  fi
  if [ -f base/docker-compose-base.yaml ]; then
    rm -f base/docker-compose-base.yaml
  fi

  touch docker-compose-e2e-template.yaml
  HEADER="#
# Copyright 2018 IBM All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the \"License\");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an \"AS IS\" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

version: '2'

"
  echo "$HEADER" >>docker-compose-e2e-template.yaml
  echo "$HEADER" >>base/docker-compose-base.yaml
  NETWORKS="networks:
  $DOCKER_NETWORK_NAME:
"
  VOLUMES="volumes:
  orderer.$DOMAIN_NAME:
  "
  SERVICES="services:
"
  echo "$SERVICES" >>base/docker-compose-base.yaml
  BASE_ORDERER="  orderer.$DOMAIN_NAME:
    container_name: orderer.$DOMAIN_NAME
    image: hyperledger/fabric-orderer:\$IMAGE_TAG
    environment:
      - ORDERER_GENERAL_LOGLEVEL=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_GENESISMETHOD=file
      - ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block
      - ORDERER_GENERAL_LOCALMSPID=${ORDERER_NAME}MSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      # enabled TLS
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric
    command: orderer
    volumes:
    - ../channel-artifacts/genesis.block:/var/hyperledger/orderer/orderer.genesis.block
    - ../crypto-config/ordererOrganizations/$DOMAIN_NAME/orderers/orderer.$DOMAIN_NAME/msp:/var/hyperledger/orderer/msp
    - ../crypto-config/ordererOrganizations/$DOMAIN_NAME/orderers/orderer.$DOMAIN_NAME/tls/:/var/hyperledger/orderer/tls
    - orderer.$DOMAIN_NAME:/var/hyperledger/production/orderer
    ports:
      - 7050:7050

"
  echo "$BASE_ORDERER" >>base/docker-compose-base.yaml
  BASE_PEERS=""
  PORT_NUMBER=7051
  for org in $ORGS_LIST; do
    VOLUMES=${VOLUMES}"peer0.${org,,}.$DOMAIN_NAME:
  "
    SERVICES=${SERVICES}"  ${org,,}-ca:
    image: hyperledger/fabric-ca:\$IMAGE_TAG
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${org,,}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_TLS_CERTFILE=/etc/hyperledger/fabric-ca-server-config/ca.${org,,}.$DOMAIN_NAME-cert.pem
      - FABRIC_CA_SERVER_TLS_KEYFILE=/etc/hyperledger/fabric-ca-server-config/${org}_CA_PRIVATE_KEY
    ports:
    - \"$((PORT_NUMBER + 3)):7054\"
    command: sh -c 'fabric-ca-server start --ca.certfile /etc/hyperledger/fabric-ca-server-config/ca.${org,,}.$DOMAIN_NAME-cert.pem --ca.keyfile /etc/hyperledger/fabric-ca-server-config/${org}_CA_PRIVATE_KEY -b admin:adminpw -d'
    volumes:
    - ./crypto-config/peerOrganizations/${org,,}.$DOMAIN_NAME/ca/:/etc/hyperledger/fabric-ca-server-config
    container_name: ca_peer$org
    networks:
    - $DOCKER_NETWORK_NAME

  peer0.${org,,}.$DOMAIN_NAME:
    container_name: peer0.${org,,}.$DOMAIN_NAME
    extends:
      file:  base/docker-compose-base.yaml
      service: peer0.${org,,}.$DOMAIN_NAME
    networks:
      - $DOCKER_NETWORK_NAME

"
    BASE_PEERS=${BASE_PEERS}"  peer0.${org,,}.$DOMAIN_NAME:
    container_name: peer0.${org,,}.$DOMAIN_NAME
    extends:
      file: peer-base.yaml
      service: peer-base
    environment:
      - CORE_PEER_ID=peer0.${org,,}.$DOMAIN_NAME
      - CORE_PEER_ADDRESS=peer0.${org,,}.$DOMAIN_NAME:7051
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0.${org,,}.$DOMAIN_NAME:7051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.${org,,}.$DOMAIN_NAME:7051
      - CORE_PEER_LOCALMSPID=${org}MSP
    volumes:
        - /var/run/:/host/var/run/
        - ../crypto-config/peerOrganizations/${org,,}.$DOMAIN_NAME/peers/peer0.${org,,}.$DOMAIN_NAME/msp:/etc/hyperledger/fabric/msp
        - ../crypto-config/peerOrganizations/${org,,}.$DOMAIN_NAME/peers/peer0.${org,,}.$DOMAIN_NAME/tls:/etc/hyperledger/fabric/tls
        - peer0.${org,,}.$DOMAIN_NAME:/var/hyperledger/production
    ports:
      - $PORT_NUMBER:7051
      - $((PORT_NUMBER + 2)):7053
      - $((PORT_NUMBER + 4)):6060

"
    PORT_NUMBER=$((PORT_NUMBER + 1000))

  done
  SERVICES=${SERVICES}"  orderer.$DOMAIN_NAME:
    extends:
      file:   base/docker-compose-base.yaml
      service: orderer.$DOMAIN_NAME
    container_name: orderer.$DOMAIN_NAME
    networks:
      - $DOCKER_NETWORK_NAME

"
  echo "$VOLUMES" >>docker-compose-e2e-template.yaml
  echo "$NETWORKS" >>docker-compose-e2e-template.yaml
  echo "$SERVICES" >>docker-compose-e2e-template.yaml
  echo "$BASE_PEERS" >>base/docker-compose-base.yaml
}

function generateNetworkFiles() {

  # Check and delete existing config files
  if [ -f crypto-config.yaml ]; then
    rm crypto-config.yaml
  fi
  if [ -f configtx.yaml ]; then
    rm configtx.yaml
  fi
  touch configtx.yaml
  touch crypto-config.yaml

  ORDERER_STRING="OrdererOrgs:
  # ---------------------------------------------------------------------------
  # $ORDERER_NAME
  # ---------------------------------------------------------------------------
  - Name: $ORDERER_NAME
    Domain: $DOMAIN_NAME
    # ---------------------------------------------------------------------------
    # \"Specs\" - See PeerOrgs below for complete description
    # ---------------------------------------------------------------------------
    Specs:
      - Hostname: orderer
      "
  echo "$ORDERER_STRING" >>crypto-config.yaml
  ORGS_STRING="PeerOrgs:
  # ---------------------------------------------------------------------------\n
"
  echo "$ORGS_STRING" >>crypto-config.yaml
  # Loop through every org and add it's info to the crypto config and configtx files
  CONFIGTX_STRING="Organizations:

    # SampleOrg defines an MSP using the sampleconfig.  It should never be used
    # in production but may be used as a template for other definitions
    - &$ORDERER_NAME
        # DefaultOrg defines the organization which is used in the sampleconfig
        # of the fabric.git development environment
        Name: $ORDERER_NAME

        # ID to load the MSP definition as
        ID: ${ORDERER_NAME}MSP

        # MSPDir is the filesystem path which contains the MSP configuration
        MSPDir: crypto-config/ordererOrganizations/$DOMAIN_NAME/msp

        # Policies for reading, writing, configuration
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${ORDERER_NAME}MSP.member')\"
            Writers:
                Type: Signature
                Rule: \"OR('${ORDERER_NAME}MSP.member')\"
            Admins:
                Type: Signature
                Rule: \"OR('${ORDERER_NAME}MSP.admin')\"

"
  echo "$CONFIGTX_STRING" >>configtx.yaml
  CON_ORGS=""
  for org in $ORGS_LIST; do
    CON_ORGS=${CON_ORGS}"
                - *$org"
    echo "Now adding $org to crypto-config.yaml file.."
    ORG="# ---------------------------------------------------------------------------
    # $org
    # ---------------------------------------------------------------------------
    - Name: $org
      Domain: ${org,,}.$DOMAIN_NAME
      EnableNodeOUs: true
      Template:
        Count: 1
      Users:
        Count: 1
    "
    echo "$ORG" >>crypto-config.yaml
    CTX_ORG="    - &$org
        # DefaultOrg defines the organization which is used in the sampleconfig
        # of the fabric.git development environment
        Name: ${org}

        # ID to load the MSP definition as
        ID: ${org}MSP

        MSPDir: crypto-config/peerOrganizations/${org,,}.$DOMAIN_NAME/msp

        # Policies for reading, writing, configuration
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${org}MSP.admin', '${org}MSP.peer', '${org}MSP.client')\"
            Writers:
                Type: Signature
                Rule: \"OR('${org}MSP.admin', '${org}MSP.client')\"
            Admins:
                Type: Signature
                Rule: \"OR('${org}MSP.admin')\"

        AnchorPeers:
            # AnchorPeers defines the location of peers which can be used
            # for cross org gossip communication.  Note, this value is only
            # encoded in the genesis block in the Application section context
            - Host: peer0.${org,,}.$DOMAIN_NAME
              Port: 7051
    "
    echo "$CTX_ORG" >>configtx.yaml
  done
  CTX_OTHR="
################################################################################
#
#   SECTION: Orderer
#
#   - This section defines the values to encode into a config transaction or
#   genesis block for orderer related parameters
#
################################################################################
Orderer: &OrdererDefaults

    # Orderer Type: The orderer implementation to start
    # Available types are \"solo\" and \"kafka\"
    OrdererType: solo

    Addresses:
        - orderer.$DOMAIN_NAME:7050

    # Batch Timeout: The amount of time to wait before creating a batch
    BatchTimeout: 2s

    # Batch Size: Controls the number of messages batched into a block
    BatchSize:

        # Max Message Count: The maximum number of messages to permit in a batch
        MaxMessageCount: 10

        # Absolute Max Bytes: The absolute maximum number of bytes allowed for
        # the serialized messages in a batch.
        AbsoluteMaxBytes: 99 MB

        # Preferred Max Bytes: The preferred maximum number of bytes allowed for
        # the serialized messages in a batch. A message larger than the preferred
        # max bytes will result in a batch larger than preferred max bytes.
        PreferredMaxBytes: 512 KB

    Kafka:
        # Brokers: A list of Kafka brokers to which the orderer connects
        # NOTE: Use IP:port notation
        Brokers:
            - 127.0.0.1:9092

    # Organizations is the list of orgs which are defined as participants on
    # the orderer side of the network
    Organizations:

    # Policies defines the set of policies at this level of the config tree
    # For Orderer policies, their canonical path is
    #   /Channel/Orderer/<PolicyName>
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"ANY Admins\"
        # BlockValidation specifies what signatures must be included in the block
        # from the orderer for the peer to validate it.
        BlockValidation:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"

################################################################################
#
#   SECTION: Application
#
#   - This section defines the values to encode into a config transaction or
#   genesis block for application related parameters
#
################################################################################
Application: &ApplicationDefaults

    # Organizations is the list of orgs which are defined as participants on
    # the application side of the network
    Organizations:

    # Policies defines the set of policies at this level of the config tree
    # For Application policies, their canonical path is
    #   /Channel/Application/<PolicyName>
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"ANY Admins\"

################################################################################
#
#   CHANNEL
#
#   This section defines the values to encode into a config transaction or
#   genesis block for channel related parameters.
#
################################################################################
Channel: &ChannelDefaults
    # Policies defines the set of policies at this level of the config tree
    # For Channel policies, their canonical path is
    #   /Channel/<PolicyName>
    Policies:
        # Who may invoke the 'Deliver' API
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        # Who may invoke the 'Broadcast' API
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        # By default, who may modify elements at this config level
        Admins:
            Type: ImplicitMeta
            Rule: \"ANY Admins\"

################################################################################
#
#   SECTION: Capabilities
#
#   - This section defines the capabilities of fabric network. This is a new
#   concept as of v1.1.0 and should not be utilized in mixed networks with
#   v1.0.x peers and orderers.  Capabilities define features which must be
#   present in a fabric binary for that binary to safely participate in the
#   fabric network.  For instance, if a new MSP type is added, newer binaries
#   might recognize and validate the signatures from this type, while older
#   binaries without this support would be unable to validate those
#   transactions.  This could lead to different versions of the fabric binaries
#   having different world states.  Instead, defining a capability for a channel
#   informs those binaries without this capability that they must cease
#   processing transactions until they have been upgraded.  For v1.0.x if any
#   capabilities are defined (including a map with all capabilities turned off)
#   then the v1.0.x peer will deliberately crash.
#
################################################################################
Capabilities:
    # Channel capabilities apply to both the orderers and the peers and must be
    # supported by both.  Set the value of the capability to true to require it.
    Global: &ChannelCapabilities
        # V1.1 for Global is a catchall flag for behavior which has been
        # determined to be desired for all orderers and peers running v1.0.x,
        # but the modification of which would cause incompatibilities.  Users
        # should leave this flag set to true.
        V1_1: true

    # Orderer capabilities apply only to the orderers, and may be safely
    # manipulated without concern for upgrading peers.  Set the value of the
    # capability to true to require it.
    Orderer: &OrdererCapabilities
        # V1.1 for Order is a catchall flag for behavior which has been
        # determined to be desired for all orderers running v1.0.x, but the
        # modification of which  would cause incompatibilities.  Users should
        # leave this flag set to true.
        V1_1: true

    # Application capabilities apply only to the peer network, and may be safely
    # manipulated without concern for upgrading orderers.  Set the value of the
    # capability to true to require it.
    Application: &ApplicationCapabilities
        # V1.1 for Application is a catchall flag for behavior which has been
        # determined to be desired for all peers running v1.0.x, but the
        # modification of which would cause incompatibilities.  Users should
        # leave this flag set to true.
        V1_2: true

################################################################################
#
#   Profile
#
#   - Different configuration profiles may be encoded here to be specified
#   as parameters to the configtxgen tool
#
################################################################################"

  echo "$CTX_OTHR" >>configtx.yaml
  CTX_PFL="Profiles:

    ${PROFILE_NAME}OrdererGenesis:
        <<: *ChannelDefaults
        Capabilities:
            <<: *ChannelCapabilities
        Orderer:
            <<: *OrdererDefaults
            Organizations:
                - *$ORDERER_NAME
            Capabilities:
                <<: *OrdererCapabilities
        Consortiums:
            ${PROFILE_NAME}Consortium:
                Organizations:$CON_ORGS
    ${PROFILE_NAME}Channel:
        Consortium: ${PROFILE_NAME}Consortium
        Application:
            <<: *ApplicationDefaults
            Organizations:$CON_ORGS
            Capabilities:
                <<: *ApplicationCapabilities
"
  echo "$CTX_PFL" >>configtx.yaml
  echo "Done creating crypto-config.yaml file"
  echo "Done generating configtx.yaml file..."
  generateDockerComposeFile
}

# channel name (overrides default 'testchainid')
CHANNEL_NAME="cartrackerchannel"
# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose-e2e.yaml
COMPOSE_FILE_NEW_ORG=add_org/docker-compose-exportingEntityOrg.yaml
DOCKER_NETWORK_NAME="mainnet"
# default image tag
IMAGETAG="latest"
# default log file
LOG_FILE="logs/network.log"
LOG_FILE_NEW_ORG="logs/network-neworg.log"
# Parse commandline args

MODE=$1
shift
# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting"
elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping"
elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting"
elif [ "$MODE" == "clean" ]; then
  EXPMODE="Cleaning"
elif [ "${MODE}" == "generateAll" ]; then ## Generate necessary files
  EXPMODE="Generating network files and artifacts"
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating certs and genesis block"
elif [ "${MODE}" == "generateNetworkFiles" ]; then ## Generate necessary files
  EXPMODE="Generating necessary network files: crypto-config.yaml, configtx.yaml"
elif [ "$MODE" == "upgrade" ]; then
  EXPMODE="Upgrading the network"
elif [ "$MODE" == "createneworg" ]; then
  EXPMODE="Generating certs and configuration for new org"
elif [ "$MODE" == "startneworg" ]; then
  EXPMODE="Starting peer and CA for new org"
elif [ "$MODE" == "stopneworg" ]; then
  EXPMODE="Stopping peer and CA for new org"
else
  printHelp
  exit 1
fi

while getopts "h?m:c:f:i:o:d:l:r:p:n:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  c)
    CHANNEL_NAME=$OPTARG
    ;;
  f)
    COMPOSE_FILE=$OPTARG
    ;;
  i)
    IMAGETAG=$(uname -m)"-"$OPTARG
    ;;
  o)
    LOG_FILE=$OPTARG
    ;;
  d)
    DEV_MODE=$OPTARG
    ;;
  l)
    ORGS_LIST=$OPTARG
    ;;
  r)
    ORDERER_NAME=$OPTARG
    ;;
  n)
    DOMAIN_NAME=$OPTARG
    ;;
  p)
    PROFILE_NAME=$OPTARG
    ;;
  esac
done

# Announce what was requested
echo "${EXPMODE} with channel '${CHANNEL_NAME}'"
# ask for confirmation to proceed
askProceed

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  generateCerts
  replacePrivateKey
  generateChannelArtifacts
elif [ "${MODE}" == "generateNetworkFiles" ]; then ## Generate necessary files
  generateNetworkFiles
elif [ "${MODE}" == "generateAll" ]; then ## Generate network files and artifacts
  generateNetworkFiles
  generateCerts
  replacePrivateKey
  generateChannelArtifacts
elif [ "${MODE}" == "restart" ]; then ## Restart the network
  networkDown
  networkUp
elif [ "${MODE}" == "reset" ]; then ## Delete chaincode containers while keeping network artifacts
  removeUnwantedImages
elif [ "${MODE}" == "clean" ]; then ## Delete network artifacts
  networkClean
elif [ "${MODE}" == "upgrade" ]; then ## Upgrade the network from v1.0.x to v1.1
  upgradeNetwork
elif [ "${MODE}" == "createneworg" ]; then ## Generate artifacts for new org
  generateCertsForNewOrg
  replacePrivateKeyForNewOrg
  generateChannelConfigForNewOrg
elif [ "${MODE}" == "startneworg" ]; then ## Start the network components for the new org
  newOrgNetworkUp
elif [ "${MODE}" == "stopneworg" ]; then ## Start the network components for the new org
  newOrgNetworkDown
else
  printHelp
  exit 1
fi