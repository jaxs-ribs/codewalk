/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React from 'react';
import { SafeAreaView, StatusBar, Text, useColorScheme, StyleSheet } from 'react-native';

function App() {
  const isDarkMode = useColorScheme() === 'dark';

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: isDarkMode ? '#000' : '#fff' }]}> 
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <Text style={[styles.text, { color: isDarkMode ? '#fff' : '#000' }]}>Hello World</Text>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  text: {
    fontSize: 24,
    fontWeight: '600',
  },
});

export default App;
