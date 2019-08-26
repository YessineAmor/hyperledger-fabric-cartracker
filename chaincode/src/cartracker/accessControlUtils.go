/*
 * Copyright 2018 IBM All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package cartracker

import (
	"crypto/x509"
	"fmt"

	"github.com/hyperledger/fabric/core/chaincode/lib/cid"
	"github.com/hyperledger/fabric/core/chaincode/shim"
)

func getTxCreatorInfo(stub shim.ChaincodeStubInterface) (string, string, error) {
	var mspid string
	var err error
	var cert *x509.Certificate

	mspid, err = cid.GetMSPID(stub)
	if err != nil {
		fmt.Printf("Error getting MSP identity: %s\n", err.Error())
		return "", "", err
	}

	cert, err = cid.GetX509Certificate(stub)
	if err != nil {
		fmt.Printf("Error getting client certificate: %s\n", err.Error())
		return "", "", err
	}

	return mspid, cert.Issuer.CommonName, nil
}

func authenticateOrg(mspID, requiredMSPID, certCN, requiredCertCN string) bool {
	return (mspID == requiredMSPID) && (certCN == requiredCertCN)
}
