# Generating Network Files
The necessary config files are:
  - crypto-config.yaml used for generating certs for our orgs
  - configtx.yaml used for generating channel artifacts
You can generate these files by executing the following command
```sh
$ ./cartracker.sh generateAll -c cartrackerchannel -r CarTrackerOrderer -l "ManufacturerOrg DealershipOrg InsuranceOrg CarRegistrationAuthorityOrg BuyerOrg" -n cartracker.com -p CarTracker
```
where
  - -p: profile_name
  - -c: channel_name
  - -r: Orderer name
  - -l: orgs list
  - -n: domain name
# Run the Network
  You can run the network by executing
```sh
$ ./cartracker.sh up
```
Check running docker containers with
```sh
$ docker ps
```
If all was successful, you should see something like this
<pre>        IMAGE                               COMMAND                  CREATED             STATUS              PORTS                                                                       NAMES
hyperledger/fabric-ca:latest        &quot;sh -c &apos;fabric-ca-se…&quot;   40 seconds ago      Up 10 seconds       0.0.0.0:10054-&gt;7054/tcp                                                     ca_peerCarRegistrationAuthorityOrg
hyperledger/fabric-ca:latest        &quot;sh -c &apos;fabric-ca-se…&quot;   40 seconds ago      Up 10 seconds       0.0.0.0:11054-&gt;7054/tcp                                                     ca_peerBuyerOrg
hyperledger/fabric-ca:latest        &quot;sh -c &apos;fabric-ca-se…&quot;   41 seconds ago      Up 10 seconds       0.0.0.0:9054-&gt;7054/tcp                                                      ca_peerInsuranceOrg
hyperledger/fabric-peer:latest      &quot;peer node start&quot;        41 seconds ago      Up 8 seconds        0.0.0.0:11055-&gt;6060/tcp, 0.0.0.0:11051-&gt;7051/tcp, 0.0.0.0:11053-&gt;7053/tcp   peer0.buyerorg.cartracker.com
hyperledger/fabric-peer:latest      &quot;peer node start&quot;        42 seconds ago      Up 8 seconds        0.0.0.0:7051-&gt;7051/tcp, 0.0.0.0:7053-&gt;7053/tcp, 0.0.0.0:7055-&gt;6060/tcp      peer0.manufacturerorg.cartracker.com
hyperledger/fabric-peer:latest      &quot;peer node start&quot;        42 seconds ago      Up 10 seconds       0.0.0.0:10055-&gt;6060/tcp, 0.0.0.0:10051-&gt;7051/tcp, 0.0.0.0:10053-&gt;7053/tcp   peer0.carregistrationauthorityorg.cartracker.com
hyperledger/fabric-ca:latest        &quot;sh -c &apos;fabric-ca-se…&quot;   42 seconds ago      Up 8 seconds        0.0.0.0:8054-&gt;7054/tcp                                                      ca_peerDealershipOrg
hyperledger/fabric-peer:latest      &quot;peer node start&quot;        42 seconds ago      Up 9 seconds        0.0.0.0:8055-&gt;6060/tcp, 0.0.0.0:8051-&gt;7051/tcp, 0.0.0.0:8053-&gt;7053/tcp      peer0.dealershiporg.cartracker.com
hyperledger/fabric-ca:latest        &quot;sh -c &apos;fabric-ca-se…&quot;   42 seconds ago      Up 11 seconds       0.0.0.0:7054-&gt;7054/tcp                                                      ca_peerManufacturerOrg
hyperledger/fabric-peer:latest      &quot;peer node start&quot;        42 seconds ago      Up 12 seconds       0.0.0.0:9055-&gt;6060/tcp, 0.0.0.0:9051-&gt;7051/tcp, 0.0.0.0:9053-&gt;7053/tcp      peer0.insuranceorg.cartracker.com
hyperledger/fabric-orderer:latest   &quot;orderer&quot;                42 seconds ago      Up 13 seconds       0.0.0.0:7050-&gt;7050/tcp                                                      orderer.cartracker.com
</pre>

#Stop the Network
You can stop the network using
```sh
$ ./cartracker.sh down
```
The command above kills all containers, removes each peer's volume and the network and removes the docker network
<pre>Stopping ca_peerCarRegistrationAuthorityOrg               ... <font color="#4E9A06">done</font>
Stopping ca_peerBuyerOrg                                  ... <font color="#4E9A06">done</font>
Stopping ca_peerInsuranceOrg                              ... <font color="#4E9A06">done</font>
Stopping peer0.buyerorg.cartracker.com                    ... <font color="#4E9A06">done</font>
Stopping peer0.manufacturerorg.cartracker.com             ... <font color="#4E9A06">done</font>
Stopping peer0.carregistrationauthorityorg.cartracker.com ... <font color="#4E9A06">done</font>
Stopping ca_peerDealershipOrg                             ... <font color="#4E9A06">done</font>
Stopping peer0.dealershiporg.cartracker.com               ... <font color="#4E9A06">done</font>
Stopping ca_peerManufacturerOrg                           ... <font color="#4E9A06">done</font>
Stopping peer0.insuranceorg.cartracker.com                ... <font color="#4E9A06">done</font>
Stopping orderer.cartracker.com                           ... <font color="#4E9A06">done</font>
Removing ca_peerCarRegistrationAuthorityOrg               ... <font color="#4E9A06">done</font>
Removing ca_peerBuyerOrg                                  ... <font color="#4E9A06">done</font>
Removing ca_peerInsuranceOrg                              ... <font color="#4E9A06">done</font>
Removing peer0.buyerorg.cartracker.com                    ... <font color="#4E9A06">done</font>
Removing peer0.manufacturerorg.cartracker.com             ... <font color="#4E9A06">done</font>
Removing peer0.carregistrationauthorityorg.cartracker.com ... <font color="#4E9A06">done</font>
Removing ca_peerDealershipOrg                             ... <font color="#4E9A06">done</font>
Removing peer0.dealershiporg.cartracker.com               ... <font color="#4E9A06">done</font>
Removing ca_peerManufacturerOrg                           ... <font color="#4E9A06">done</font>
Removing peer0.insuranceorg.cartracker.com                ... <font color="#4E9A06">done</font>
Removing orderer.cartracker.com                           ... <font color="#4E9A06">done</font>
Removing network network_mainnet
Removing volume network_orderer.cartracker.com
Removing volume network_peer0.insuranceorg.cartracker.com
Removing volume network_peer0.dealershiporg.cartracker.com
Removing volume network_peer0.manufacturerorg.cartracker.com
Removing volume network_peer0.carregistrationauthorityorg.cartracker.com
Removing volume network_peer0.buyerorg.cartracker.com
</pre>
