using KcdMp.Server.Features.Client;
using KcdMp.Server.Features.Tcp;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace KcdMp.Server;

class Program
{
	static async Task Main(string[] args)
	{
		var builder = Host.CreateApplicationBuilder(args);
		
		// Logging config
		builder.Services.AddSerilog(options =>
		{
			options.ReadFrom.Configuration(builder.Configuration);
		});
		
		// Add TCP Socket as background service
		builder.Services.AddHostedService<TcpSocketService>();
		
		// 
		builder.Services.AddSingleton<ClientHandler>();
		builder.Services.AddSingleton<TcpBroadcastService>();
		
		using var app = builder.Build();
		
		await app.RunAsync();
	}
}