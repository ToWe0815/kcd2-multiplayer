namespace KcdMp.Server.Features.Client;

public class ClientHandler
{
	private readonly IList<ClientSession> _clients = [];
	
	public void AddClient(ClientSession client) => 
		_clients.Add(client);
	
	public void RemoveClient(ClientSession client) => 
		_clients.Remove(client);
	
	public ClientSession[] GetClients() =>
		_clients.ToArray();

	public int ClientCount =>
		_clients.Count;
}