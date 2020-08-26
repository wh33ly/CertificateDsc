[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
param ()

$script:dscModuleName = 'CertificateDsc'
$script:dscResourceName = 'DSC_PfxImport'

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force -ErrorAction 'Stop'
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:dscModuleName `
        -DSCResourceName $script:dscResourceName `
        -ResourceType 'Mof' `
        -TestType 'Unit'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers\CommonTestHelper.psm1')
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

# Begin Testing
try
{
    InModuleScope $script:dscResourceName {
        $definedRuntimeTypes = ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object -FilterScript { $null -ne $_.DefinedTypes }).GetTypes()
        $validThumbprint = (
            $definedRuntimeTypes | Where-Object -FilterScript {
                $_.BaseType.BaseType -eq [System.Security.Cryptography.HashAlgorithm] -and
                ($_.Name -cmatch 'Managed$' -or $_.Name -cmatch 'Provider$')
            } | Select-Object -First 1 | ForEach-Object -Process {
                (New-Object $_).ComputeHash([String]::Empty) | ForEach-Object -Process {
                    '{0:x2}' -f $_
                }
            }
        ) -join ''

        $testFile = 'test.pfx'

        $testUsername = 'DummyUsername'
        $testPassword = 'DummyPassword'
        $testCredential = New-Object `
            -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $testUsername, (ConvertTo-SecureString $testPassword -AsPlainText -Force)

        $validPath = "TestDrive:\$testFile"
        $validCertPath = "Cert:\LocalMachine\My"
        $validCertFullPath = '{0}\{1}' -f $validCertPath, $validThumbprint

        $certificateFriendlyName = 'Test Certificate Friendly Name'

        $validCertificateWithPrivateKey_mock = {
            @{
                Thumbprint    = $validThumbprint
                HasPrivateKey = $true
                FriendlyName  = $certificateFriendlyName
            }
        }

        $validCertificateWithoutPrivateKey_mock = {
            @{
                Thumbprint    = $validThumbprint
                HasPrivateKey = $false
                FriendlyName  = $certificateFriendlyName
            }
        }

        $validCertificateWithDifferentFriendlyName_mock = {
            @{
                Thumbprint    = $validThumbprint
                HasPrivateKey = $true
                FriendlyName  = 'Different Friendly Name'
            }
        }

        $testPath_parameterfilter = {
            $Path -eq $validPath
        }

        $getCertificateFromCertificateStore_parameterfilter = {
            $Thumbprint -eq $validThumbprint -and `
                $Location -eq 'LocalMachine' -and `
                $Store -eq 'My'
        }

        $importPfxCertificate_parameterfilter = {
            $CertStoreLocation -eq $validCertPath -and `
                $FilePath -eq $validPath -and `
                $Exportable -eq $True -and `
                $Password -eq $testCredential.Password
        }

        $setCertificateFriendlyNameInCertificateStore_parameterfilter = {
            $Thumbprint -eq $validThumbprint -and `
                $Location -eq 'LocalMachine' -and `
                $Store -eq 'My' -and `
                $FriendlyName -eq $certificateFriendlyName
        }

        $removeCertificateFromCertificateStore_parameterfilter = {
            $Location -eq 'LocalMachine' -and `
                $Store -eq 'My' -and `
                $Thumbprint -eq $validThumbprint
        }

        $presentParams = @{
            Thumbprint = $validThumbprint
            Path       = $validPath
            Ensure     = 'Present'
            Location   = 'LocalMachine'
            Store      = 'My'
            Exportable = $True
            Credential = $testCredential
            Verbose    = $True
        }

        $presentParamsWithFriendlyName = @{
            Thumbprint   = $validThumbprint
            Path         = $validPath
            Ensure       = 'Present'
            Location     = 'LocalMachine'
            Store        = 'My'
            Exportable   = $True
            Credential   = $testCredential
            Verbose      = $True
            FriendlyName = $certificateFriendlyName
        }

        $absentParams = @{
            Thumbprint = $validThumbprint
            Ensure     = 'Absent'
            Location   = 'LocalMachine'
            Store      = 'My'
            Verbose    = $True
        }

        Describe 'DSC_PfxImport\Get-TargetResource' -Tag 'Get' {
            Context 'When the certificate exists with a private key' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should not throw exception' {
                    {
                        $script:result = Get-TargetResource @presentParams
                    } | Should -Not -Throw
                }

                It 'Should return a hashtable' {
                    $script:result | Should -BeOfType System.Collections.Hashtable
                }

                It 'Should contain the input values' {
                    $script:result.Thumbprint | Should -BeExactly $validThumbprint
                    $script:result.Path | Should -BeExactly $validPath
                    $script:result.Ensure | Should -BeExactly 'Present'
                    $script:result.FriendlyName | Should -BeExactly $certificateFriendlyName
                }

                It 'Should call the expected mocks' {
                    Assert-MockCalled `
                        -CommandName Get-CertificateFromCertificateStore `
                        -ParameterFilter $getCertificateFromCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }
            }

            Context 'When the certificate exists without private key' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithoutPrivateKey_mock

                It 'Should not throw exception' {
                    {
                        $script:result = Get-TargetResource @presentParams
                    } | Should -Not -Throw
                }

                It 'Should return a hashtable' {
                    $script:result | Should -BeOfType System.Collections.Hashtable
                }

                It 'Should contain the input values' {
                    $script:result.Thumbprint | Should -BeExactly $validThumbprint
                    $script:result.Path | Should -BeExactly $validPath
                    $script:result.Ensure | Should -BeExactly 'Absent'
                    $script:result.FriendlyName | Should -BeExactly $certificateFriendlyName
                }

                It 'Should call the expected mocks' {
                    Assert-MockCalled `
                        -CommandName Get-CertificateFromCertificateStore `
                        -ParameterFilter $getCertificateFromCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }
            }

            Context 'When the certificate does not exist' {
                Mock -CommandName Get-CertificateFromCertificateStore

                It 'Should not throw exception' {
                    {
                        $script:result = Get-TargetResource @presentParams
                    } | Should -Not -Throw
                }

                It 'Should return a hashtable' {
                    $script:result | Should -BeOfType System.Collections.Hashtable
                }

                It 'Should contain the input values' {
                    $script:result.Thumbprint | Should -BeExactly $validThumbprint
                    $script:result.Path | Should -BeExactly $validPath
                    $script:result.Ensure | Should -BeExactly 'Absent'
                    $script:result.FriendlyName | Should -BeNullOrEmpty
                }

                It 'Should call the expected mocks' {
                    Assert-MockCalled `
                        -CommandName Get-CertificateFromCertificateStore `
                        -ParameterFilter $getCertificateFromCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }
            }
        }

        Describe 'DSC_PfxImport\Test-TargetResource' -Tag 'Test' {
            Context 'When certificate is not in store but should be' {
                Mock -CommandName Get-CertificateFromCertificateStore

                It 'Should return false' {
                    Test-TargetResource @presentParams | Should -Be $false
                }
            }

            Context 'When certificate is not in store and should not be' {
                Mock -CommandName Get-CertificateFromCertificateStore

                It 'Should return true' {
                    Test-TargetResource @absentParams | Should -Be $true
                }
            }

            Context 'When certificate is in store and should be' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should return true' {
                    Test-TargetResource @presentParams | Should -Be $true
                }
            }

            Context 'When certificate is in store and should be and the FriendlyName is correct' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should return true' {
                    Test-TargetResource @presentParamsWithFriendlyName | Should -Be $true
                }
            }

            Context 'When certificate is in store and should be but the Friendlyname is different' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithDifferentFriendlyName_mock

                It 'Should return false' {
                    Test-TargetResource @presentParamsWithFriendlyName | Should -Be $false
                }
            }

            Context 'When certificate is in store but should not be' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should return false' {
                    Test-TargetResource @absentParams | Should -Be $false
                }
            }
        }

        Describe 'DSC_PfxImport\Set-TargetResource' -Tag 'Set' {
            BeforeAll {
                Mock -CommandName Test-Path -MockWith { $true }
                Mock -CommandName Import-PfxCertificate
                Mock -CommandName Remove-CertificateFromCertificateStore
                Mock -CommandName Set-CertificateFriendlyNameInCertificateStore
            }

            Context 'When PFX file exists and certificate should be in the store but is not' {
                Mock -CommandName Get-CertificateFromCertificateStore

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @presentParams
                    } | Should -Not -Throw
                }

                It 'Should call Test-Path with expected parameters' {
                    Assert-MockCalled `
                        -CommandName Test-Path `
                        -ParameterFilter $testPath_parameterfilter `
                        -Exactly -Times 1
                }

                It 'Should call Import-PfxCertificate with expected parameters' {
                    Assert-MockCalled `
                        -CommandName Import-PfxCertificate `
                        -ParameterFilter $importPfxCertificate_parameterfilter `
                        -Exactly -Times 1
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should not call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled -CommandName Remove-CertificateFromCertificateStore -Exactly -Times 0
                }
            }

            Context 'When PFX file exists and certificate should be in the store and is' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @presentParams
                    } | Should -Not -Throw
                }

                It 'Should not call Test-Path with expected parameters' {
                    Assert-MockCalled -CommandName Test-Path -Exactly -Times 0
                }

                It 'Should not call Import-PfxCertificate with expected parameters' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should not call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled -CommandName Remove-CertificateFromCertificateStore -Exactly -Times 0
                }
            }

            Context 'When PFX file exists and certificate should be in the store and is and the friendly name is different' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithDifferentFriendlyName_mock

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @presentParamsWithFriendlyName
                    } | Should -Not -Throw
                }

                It 'Should not call Test-Path with the parameters supplied' {
                    Assert-MockCalled -CommandName Test-Path -Exactly -Times 0
                }

                It 'Should not call Import-PfxCertificate with the parameters supplied' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should call Set-CertificateFriendlyNameInCertificateStore with expected parameters' {
                    Assert-MockCalled `
                        -CommandName Set-CertificateFriendlyNameInCertificateStore `
                        -ParameterFilter $setCertificateFriendlyNameInCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }

                It 'Should not call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled -CommandName Remove-CertificateFromCertificateStore -Exactly -Times 0
                }
            }

            Context 'When PFX file exists and certificate should be in the store and is and the friendly name is the same' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @presentParamsWithFriendlyName
                    } | Should -Not -Throw
                }

                It 'Should not call Test-Path with the parameters supplied' {
                    Assert-MockCalled -CommandName Test-Path -Exactly -Times 0
                }

                It 'Should not call Import-PfxCertificate with the parameters supplied' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should not call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled -CommandName Remove-CertificateFromCertificateStore -Exactly -Times 0
                }
            }


            Context 'When PFX file exists and certificate should not be in the store but is' {
                Mock -CommandName Get-CertificateFromCertificateStore `
                    -MockWith $validCertificateWithPrivateKey_mock

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @absentParams
                    } | Should -Not -Throw
                }

                It 'Should not call Test-Path' {
                    Assert-MockCalled -CommandName Test-Path -Exactly -Times 0
                }

                It 'Should not call Import-PfxCertificate' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should call Remove-CertificateFromCertificateStore with expected parameters' {
                    Assert-MockCalled `
                        -CommandName Remove-CertificateFromCertificateStore `
                        -ParameterFilter $removeCertificateFromCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }
            }

            Context 'When PFX file exists and certificate should not be in the store and is not' {
                Mock -CommandName Get-CertificateFromCertificateStore

                It 'Should not throw exception' {
                    {
                        Set-TargetResource @absentParams
                    } | Should -Not -Throw
                }

                It 'Should not call Test-Path' {
                    Assert-MockCalled -CommandName Test-Path -Exactly -Times 0
                }

                It 'Should not call Import-PfxCertificate' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled `
                        -CommandName Remove-CertificateFromCertificateStore `
                        -ParameterFilter $removeCertificateFromCertificateStore_parameterfilter `
                        -Exactly -Times 1
                }
            }

            Context 'When PFX file does not exist and certificate should be in the store' {
                Mock -CommandName Get-CertificateFromCertificateStore

                Mock -CommandName Test-Path -MockWith { $false }

                It 'Should throw exception' {
                    {
                        Set-TargetResource @presentParams
                    } | Should -Throw ($script:localizedData.CertificatePfxFileNotFoundError -f $validPath)
                }

                It 'Should call Test-Path with expected parameters' {
                    Assert-MockCalled `
                        -CommandName Test-Path `
                        -ParameterFilter $testPath_parameterfilter `
                        -Exactly -Times 1
                }

                It 'Should not call Import-PfxCertificate' {
                    Assert-MockCalled -CommandName Import-PfxCertificate -Exactly -Times 0
                }

                It 'Should not call Set-CertificateFriendlyNameInCertificateStore' {
                    Assert-MockCalled -CommandName Set-CertificateFriendlyNameInCertificateStore -Exactly -Times 0
                }

                It 'Should not call Remove-CertificateFromCertificateStore' {
                    Assert-MockCalled -CommandName Remove-CertificateFromCertificateStore -Exactly -Times 0
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
