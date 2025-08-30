const path = require('path');
module.exports = {
  presets: ['module:@react-native/babel-preset'],
  plugins: [
    ['inline-dotenv', { path: path.resolve(__dirname, '..', '..', '.env') }],
  ],
};
