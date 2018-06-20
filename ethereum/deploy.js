const HDWalletProvider = require('truffle-hdwallet-provider');
const Web3 = require('web3');

const provider = new HDWalletProvider(
    'borrow general parade loop more produce repair second accident pluck olympic scrub',
    'https://rinkeby.infura.io/fNl1zmU0sLaXyDH2jb77'
);

const web3 = new Web3(provider);

const deploy = async () => {

};

deploy();