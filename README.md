# Car Tracker
Hyperledger Fabric application for tracking cars history from manufacturers to owners.

# Orgs
  - ManufacturerOrg
  - DealershipOrg
  - BuyerOrg
  - InsuranceOrg
  - CarRegistryAuthorityOrg
# Sample Workflow
  1. Manufcaturer creates car
  2. Dealership buys car from manufacturer
  3. Car Registry Authority changes car owner
  4. Customer buys car from dealership and agrees with InsuranceOrg
  5. Car Registry Authority changes car owner and sets the insurance org
  6. InsuranceOrg adds repair work after an accident
# To Do
  * All payements happen on blockchain - remove car registry authority
