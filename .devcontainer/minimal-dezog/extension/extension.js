const vscode = require('vscode');

class DeZogDebugAdapterDescriptorFactory implements vscode.DebugAdapterDescriptorFactory {
  createDebugAdapterDescriptor(session: vscode.DebugSession): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
    const port = session.configuration.port || 49152;
    return new vscode.DebugAdapterServer(port, 127);
  }
}

function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory('dezog', new DeZogDebugAdapterDescriptorFactory())
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
